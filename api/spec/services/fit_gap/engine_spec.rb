# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FitGap::Engine do
  let(:organization) { create_organization('acme') }
  let(:gemini) do
    double('gemini', generate_content: { 'culture_narrative' => 'Culture text', 'overall_narrative' => 'Overall text' })
  end

  def comparisons_for(portfolio, vacancy)
    described_class.new(portfolio: portfolio, vacancy: vacancy, gemini_client: gemini)
                   .call.reload.skill_comparisons
  end

  def row(comparisons, label)
    comparisons.find { |c| c['skill_label'] == label }
  end

  it 'marks a skill the assessor overrode, using the overridden level' do
    portfolio = create_portfolio(organization, skills: [{ label: 'React', level: 2 }])
    skill = portfolio.portfolio_skills.first
    AssessorOverride.create!(portfolio_skill: skill, ai_level: 2, override_level: 4, overridden_by: 1)
    vacancy = create_vacancy(organization, skills: [{ label: 'React', level: 3 }])

    react = row(comparisons_for(portfolio, vacancy), 'React')

    expect(react).to include('candidate_level' => 4, 'result' => 'exceed', 'delta' => 1, 'overridden' => true)
  end

  it 'does not mark skills that kept the AI rating' do
    portfolio = create_portfolio(organization, skills: [{ label: 'React', level: 2 }])
    vacancy = create_vacancy(organization, skills: [{ label: 'React', level: 3 }])

    react = row(comparisons_for(portfolio, vacancy), 'React')

    expect(react).to include('candidate_level' => 2, 'result' => 'gap', 'delta' => -1, 'overridden' => false)
  end

  it 'reports a skill that was never assessed as not_assessed, not as a gap' do
    portfolio = create_portfolio(organization, skills: [{ label: 'React', level: 3 }])
    vacancy = create_vacancy(organization, skills: [{ label: 'Kubernetes', level: 3 }])

    kubernetes = row(comparisons_for(portfolio, vacancy), 'Kubernetes')

    expect(kubernetes).to include(
      'candidate_level' => nil, 'result' => 'not_assessed', 'delta' => nil, 'expected_level' => 3, 'overridden' => false
    )
  end

  it 'falls back to a plain narrative when the model call fails' do
    allow(gemini).to receive(:generate_content).and_raise(StandardError, 'model down')
    portfolio = create_portfolio(organization, skills: [{ label: 'React', level: 3 }])
    vacancy = create_vacancy(organization, skills: [{ label: 'React', level: 3 }])

    report = described_class.new(portfolio: portfolio, vacancy: vacancy, gemini_client: gemini).call

    expect(report.culture_narrative).to be_nil
    expect(report.overall_narrative).to match(/1 skill matches/)
  end
end
