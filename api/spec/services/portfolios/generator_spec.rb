# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portfolios::Generator do
  let(:organization) { create_organization('acme') }
  let(:session) do
    create_interview(organization, skills: [
      { id: 'sk-react', label: 'React', state: 'covered',   probes: 3 },
      { id: 'sk-sql',   label: 'SQL',   state: 'not_yet',   probes: 0 }
    ])
  end

  def rated(id, label, level: 3, confidence: 'high', summary: 'Works independently.')
    {
      'skill_id' => id, 'skill_label' => label, 'level' => level, 'confidence' => confidence,
      'evidence' => ['I debug with the profiler'], 'competency_summary' => summary
    }
  end

  def reply(configured: [], discovered: [])
    { 'configured_skills' => configured, 'discovered_skills' => discovered }
  end

  def generate(model_reply, for_session: session)
    gemini = double('gemini', generate_content: model_reply)
    described_class.new(session: for_session, gemini_client: gemini).call
  end

  def saved_labels(portfolio)
    portfolio.reload.portfolio_skills.map(&:skill_label).sort
  end

  describe 'rating skills' do
    it 'saves a rating for a skill that was discussed' do
      portfolio = generate(reply(configured: [rated('sk-react', 'React', level: 4)]))

      react = portfolio.portfolio_skills.find_by!(skill_label: 'React')
      expect(react.ai_level).to eq(4)
      expect(portfolio.reload).to be_complete
    end

    it "derives confidence from the interview, not from the model's claim" do
      thin = create_interview(organization, skills: [{ id: 'sk-react', label: 'React', state: 'initiated', probes: 1 }])

      portfolio = generate(reply(configured: [rated('sk-react', 'React', confidence: 'high')]), for_session: thin)

      expect(portfolio.portfolio_skills.first.ai_confidence).to eq('low')
    end

    it 'does not invent a rating for a skill that was never discussed' do
      portfolio = generate(reply(configured: [rated('sk-react', 'React'), rated('sk-sql', 'SQL', level: 3)]))

      expect(saved_labels(portfolio)).to eq(['React'])
      expect(portfolio.unassessed_skills.map(&:skill_label)).to eq(['SQL'])
    end

    it 'does not turn a missing or unreadable level into L1' do
      [nil, '', 'abc', 0, 9].each do |bad_level|
        # A fresh interview each time: a finished portfolio is (correctly) not regenerated.
        interview = create_interview(organization, skills: [{ id: 'sk-react', label: 'React', state: 'covered', probes: 3 }])

        portfolio = generate(reply(configured: [rated('sk-react', 'React', level: bad_level)]), for_session: interview)

        expect(saved_labels(portfolio)).to eq([]), "level #{bad_level.inspect} was saved"
        expect(portfolio.unassessed_skills.map(&:skill_label)).to eq(['React'])
      end
    end

    it 'accepts levels written as text, such as "L3"' do
      portfolio = generate(reply(configured: [rated('sk-react', 'React', level: 'L3')]))

      expect(portfolio.portfolio_skills.first.ai_level).to eq(3)
    end
  end

  describe 'when saving fails half-way' do
    let(:two_covered) do
      create_interview(organization, skills: [
        { id: 'sk-react', label: 'React', state: 'covered', probes: 3 },
        { id: 'sk-sql',   label: 'SQL',   state: 'covered', probes: 3 }
      ])
    end

    it 'leaves no partial portfolio behind and marks it failed' do
      broken = reply(configured: [rated('sk-react', 'React'), rated('sk-sql', 'SQL', summary: nil)])

      expect { generate(broken, for_session: two_covered) }.to raise_error(ActiveRecord::RecordInvalid)

      portfolio = two_covered.reload.portfolio
      expect(portfolio.portfolio_skills.count).to eq(0)
      expect(portfolio).to be_failed
    end
  end

  describe 'when the model answers with something unreadable' do
    let(:secret) { 'my salary is secret-12345' }

    it 'stores a fixed sentence, not the model output' do
      expect { generate("Candidate said: #{secret}") }.to raise_error(JSON::ParserError)

      portfolio = session.reload.portfolio
      expect(portfolio).to be_failed
      expect(portfolio.generation_error).to eq('The AI returned an unreadable result.')
    end

    it 'does not write the model output to the log' do
      logged = []
      allow(Rails.logger).to receive(:error) { |message| logged << message.to_s }

      expect { generate("Candidate said: #{secret}") }.to raise_error(JSON::ParserError)

      expect(logged.join(' ')).not_to include('secret-12345')
    end

    it 'treats a JSON answer of the wrong shape as unreadable too' do
      expect { generate(['not', 'an', 'object']) }.to raise_error(Portfolios::Generator::InvalidResponse)

      expect(session.reload.portfolio.generation_error).to eq('The AI returned an unreadable result.')
    end
  end

  describe 'running more than once' do
    it 'does nothing for a portfolio that is already complete' do
      session.create_portfolio!(generation_status: 'complete')
      gemini = double('gemini')
      expect(gemini).not_to receive(:generate_content)

      described_class.new(session: session, gemini_client: gemini).call

      expect(session.reload.portfolio).to be_complete
    end

    it 'does nothing while another run is in progress' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 1.minute.ago)
      gemini = double('gemini')
      expect(gemini).not_to receive(:generate_content)

      described_class.new(session: session, gemini_client: gemini).call
    end

    it 'takes over a run that has been stuck for too long' do
      session.create_portfolio!(generation_status: 'generating', generation_started_at: 20.minutes.ago)
      gemini = double('gemini')
      expect(gemini).to receive(:generate_content).once.and_return(reply(configured: [rated('sk-react', 'React')]))

      described_class.new(session: session, gemini_client: gemini).call

      expect(session.reload.portfolio).to be_complete
    end
  end
end
