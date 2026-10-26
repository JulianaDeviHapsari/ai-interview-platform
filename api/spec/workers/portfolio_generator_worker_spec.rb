# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PortfolioGeneratorWorker do
  it 'records a fixed reason, not the raw error message, when retries run out' do
    organization = create_organization('acme')
    session = create_interview(organization, skills: [{ id: 'sk-react', label: 'React', state: 'covered', probes: 3 }])
    session.create_portfolio!(generation_status: 'generating', generation_started_at: Time.current)
    job = {
      'args' => [session.id], 'retry_count' => 3,
      'error_class' => 'JSON::ParserError',
      'error_message' => "unexpected token at 'my salary is secret-12345'"
    }

    described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('x'))

    error = session.reload.portfolio.generation_error
    expect(error).to eq('The AI returned an unreadable result.')
    expect(error).not_to include('secret-12345')
  end
end
