# frozen_string_literal: true

require 'rails_helper'

# generation_error is shown to assessors and returned by the API. It must be a
# fixed, human-readable sentence, never an exception message: JSON parser errors
# quote the text the model returned, which can contain the candidate's own words.
RSpec.describe Portfolios::FailureReason do
  it 'describes an unreadable model answer without quoting it' do
    error = begin
      JSON.parse("Candidate said: my salary is 99999")
    rescue JSON::ParserError => e
      e
    end

    reason = described_class.for(error.class.name)

    expect(reason).to eq('The AI returned an unreadable result.')
    expect(reason).not_to include('99999')
  end

  it 'maps AI service failures to short, safe sentences' do
    expect(described_class.for('Gemini::HttpClient::TimeoutError')).to match(/timed out/i)
    expect(described_class.for('Gemini::HttpClient::RateLimitError')).to match(/rate limited/i)
    expect(described_class.for('Gemini::HttpClient::ApiError')).to match(/AI service/i)
  end

  it 'falls back to a generic sentence for anything unknown' do
    expect(described_class.for('SomethingWeird')).to eq('Portfolio generation failed unexpectedly.')
    expect(described_class.for(nil)).to eq('Portfolio generation failed unexpectedly.')
  end
end
