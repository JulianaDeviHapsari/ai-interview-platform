# frozen_string_literal: true

require 'rails_helper'

# Confidence says how much evidence backs a rating. It is derived from how the
# interview actually went (coverage state and number of probes), not from the
# model's own claim, so the same interview always gets the same confidence.
RSpec.describe Portfolios::Confidence do
  def map(state, probes)
    CoverageMap.new(state: state, probe_count: probes)
  end

  {
    ['covered', 3]   => 'high',
    ['covered', 5]   => 'high',
    ['covered', 2]   => 'medium',
    ['partial', 1]   => 'medium',
    ['partial', 4]   => 'medium',
    ['initiated', 2] => 'medium',
    ['initiated', 1] => 'low',
    ['not_yet', 0]   => 'low'
  }.each do |(state, probes), expected|
    it "is #{expected} for a #{state} skill probed #{probes} time(s)" do
      expect(described_class.for(map(state, probes))).to eq(expected)
    end
  end

  it 'is low when there is no coverage record to base it on' do
    expect(described_class.for(nil)).to eq('low')
  end
end
