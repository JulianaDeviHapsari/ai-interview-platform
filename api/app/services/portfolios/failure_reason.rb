# frozen_string_literal: true

module Portfolios
  # Fixed, human-readable reasons a portfolio failed to generate.
  #
  # Never store or log an exception *message* for these failures: parser errors
  # quote the text the model returned, which can include the candidate's own words
  # (personal data). The exception class alone is enough to pick a sentence.
  module FailureReason
    GENERIC = 'Portfolio generation failed unexpectedly.'

    REASONS = {
      'JSON::ParserError'                      => 'The AI returned an unreadable result.',
      'Portfolios::Generator::InvalidResponse' => 'The AI returned an unreadable result.',
      'Gemini::HttpClient::TimeoutError'       => 'The AI service timed out.',
      'Gemini::HttpClient::RateLimitError'     => 'The AI service is rate limited. Please try again shortly.',
      'Gemini::HttpClient::ApiError'           => 'The AI service returned an error.'
    }.freeze

    def self.for(class_name)
      REASONS.fetch(class_name.to_s, GENERIC)
    end
  end
end
