# frozen_string_literal: true

module Portfolios
  # How much evidence backs a rating, derived from how the interview actually went.
  # The same rule the generation prompt describes, applied by us instead of asking
  # the model to apply it to itself, so the same interview always scores the same.
  module Confidence
    def self.for(coverage_map)
      return 'low' if coverage_map.nil?
      return 'high' if coverage_map.state == 'covered' && coverage_map.probe_count >= 3
      return 'medium' if coverage_map.probe_count == 2 || coverage_map.state == 'partial'

      'low'
    end
  end
end
