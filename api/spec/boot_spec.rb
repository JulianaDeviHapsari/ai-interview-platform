# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application boot' do
  it 'can load every class (as production does) without naming errors' do
    expect { Zeitwerk::Loader.eager_load_all }.not_to raise_error
  end

  it 'finds the websocket middleware under their real names' do
    expect(AudioWebSocketMiddleware).to be_a(Class)
    expect(CoverageWebSocketMiddleware).to be_a(Class)
  end
end
