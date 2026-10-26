# frozen_string_literal: true

require 'rails_helper'

# A user of one organization must never read or change another organization's
# candidate data, even when they guess a valid portfolio / skill id.
RSpec.describe 'Tenant isolation of portfolio endpoints', type: :request do
  let(:acme)   { create_organization('acme') }
  let(:globex) { create_organization('globex') }

  let!(:acme_portfolio)   { create_portfolio(acme, skills: [{ label: 'Acme React', level: 3 }]) }
  let!(:globex_portfolio) { create_portfolio(globex, skills: [{ label: 'Globex Secret Skill', level: 4 }]) }
  let!(:acme_vacancy)     { create_vacancy(acme) }
  let(:globex_vacancy)    { create_vacancy(globex) }

  let(:acme_headers) { auth_headers(acme) }

  before { allow(FitGapGeneratorWorker).to receive(:perform_async) }

  describe 'GET /api/v1/portfolios/:id/export' do
    it "does not export another organization's portfolio" do
      get "/api/v1/portfolios/#{globex_portfolio.id}/export", params: { format: 'json' }, headers: acme_headers

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Globex Secret Skill')
    end

    it "still exports the caller's own portfolio" do
      get "/api/v1/portfolios/#{acme_portfolio.id}/export", params: { format: 'json' }, headers: acme_headers

      expect(response).to have_http_status(:ok)
      labels = JSON.parse(response.body).dig('portfolio', 'skills').map { |s| s['skill_label'] }
      expect(labels).to eq(['Acme React'])
    end
  end

  describe 'POST /api/v1/portfolio_skills/:id/override' do
    let(:override_body) { { override: { override_level: 5, assessor_notes: 'Not my candidate' } }.to_json }

    it "does not let one organization override another organization's rating" do
      foreign_skill = globex_portfolio.portfolio_skills.first

      post "/api/v1/portfolio_skills/#{foreign_skill.id}/override", params: override_body, headers: acme_headers

      expect(response).to have_http_status(:not_found)
      expect(AssessorOverride.count).to eq(0)
    end

    it "still lets the caller override their own portfolio's rating" do
      own_skill = acme_portfolio.portfolio_skills.first

      post "/api/v1/portfolio_skills/#{own_skill.id}/override", params: override_body, headers: acme_headers

      expect(response).to have_http_status(:created)
      expect(own_skill.reload.assessor_override.override_level).to eq(5)
    end
  end

  describe 'POST /api/v1/portfolios/:id/fitgap' do
    it "does not start a fit/gap report on another organization's portfolio" do
      post "/api/v1/portfolios/#{globex_portfolio.id}/fitgap",
           params: { fitgap: { vacancy_id: acme_vacancy.id } }.to_json, headers: acme_headers

      expect(response).to have_http_status(:not_found)
      expect(FitGapGeneratorWorker).not_to have_received(:perform_async)
    end

    it "queues a report for the caller's own portfolio" do
      post "/api/v1/portfolios/#{acme_portfolio.id}/fitgap",
           params: { fitgap: { vacancy_id: acme_vacancy.id } }.to_json, headers: acme_headers

      expect(response).to have_http_status(:accepted)
      expect(FitGapGeneratorWorker).to have_received(:perform_async).with(acme_portfolio.id, acme_vacancy.id)
    end
  end

  describe 'POST /api/v1/portfolios/:id/regenerate_fitgap' do
    it "does not queue a regeneration for another organization's portfolio" do
      post "/api/v1/portfolios/#{globex_portfolio.id}/regenerate_fitgap",
           params: { vacancy_id: acme_vacancy.id }.to_json, headers: acme_headers

      expect(response).to have_http_status(:not_found)
      expect(FitGapGeneratorWorker).not_to have_received(:perform_async)
    end
  end

  describe 'GET /api/v1/portfolios/:id/fitgap/:vacancy_id' do
    it "does not show another organization's report" do
      FitGapReport.create!(
        portfolio: globex_portfolio, vacancy: globex_vacancy, skill_comparisons: [{ skill_label: 'Globex Secret Skill' }]
      )

      get "/api/v1/portfolios/#{globex_portfolio.id}/fitgap/#{globex_vacancy.id}", headers: acme_headers

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Globex Secret Skill')
    end
  end
end
