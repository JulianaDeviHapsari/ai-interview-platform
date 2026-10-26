# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Portfolio status endpoints', type: :request do
  let(:organization) { create_organization('acme') }
  let(:headers)      { auth_headers(organization) }
  let(:session) do
    create_interview(organization, skills: [
      { id: 'sk-react', label: 'React', state: 'covered', probes: 3 },
      { id: 'sk-sql',   label: 'SQL',   state: 'not_yet', probes: 0 }
    ])
  end

  before { allow(PortfolioGeneratorWorker).to receive(:perform_async) }

  def body
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/sessions/:id/portfolio' do
    it 'says generating while a recent run is in progress' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 1.minute.ago)

      get "/api/v1/sessions/#{session.id}/portfolio", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(body['status']).to eq('generating')
    end

    it 'reports a run stuck for too long as failed instead of generating forever' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 20.minutes.ago)

      get "/api/v1/sessions/#{session.id}/portfolio", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body.dig('portfolio', 'generation_status')).to eq('failed')
      expect(body.dig('portfolio', 'generation_error')).to match(/took too long/i)
    end

    it 'lists configured skills that were never assessed' do
      portfolio = session.create_portfolio!(generation_status: 'complete')
      portfolio.portfolio_skills.create!(
        skill_id: 'sk-react', skill_label: 'React', ai_level: 3, ai_confidence: 'high',
        competency_summary: 'Works independently.', evidence: []
      )

      get "/api/v1/sessions/#{session.id}/portfolio", headers: headers

      expect(body.dig('portfolio', 'unassessed_skills')).to eq([{ 'skill_id' => 'sk-sql', 'skill_label' => 'SQL' }])
    end
  end

  describe 'POST /api/v1/sessions/:id/portfolio/regenerate' do
    it 'lets the assessor retry a run that is stuck' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 20.minutes.ago)

      post "/api/v1/sessions/#{session.id}/portfolio/regenerate", headers: headers

      expect(response).to have_http_status(:ok)
      expect(PortfolioGeneratorWorker).to have_received(:perform_async).with(session.id)
    end

    it 'refuses to start a second run while one is genuinely in progress' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 1.minute.ago)

      post "/api/v1/sessions/#{session.id}/portfolio/regenerate", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(PortfolioGeneratorWorker).not_to have_received(:perform_async)
    end
  end
end
