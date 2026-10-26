# frozen_string_literal: true

# Small builders for the records most specs need. Plain methods rather than
# FactoryBot so every record's required fields stay visible in one place.
module DomainHelpers
  def create_organization(scheme)
    Organization.create!(
      name:       scheme.capitalize,
      scheme:     scheme,
      identifier: scheme,
      host:       "#{scheme}.example.test"
    )
  end

  # JWT accepted by the API for a user of the given organization.
  def auth_headers(organization, role: 'admin')
    token = JsonWebToken.encode({ user_id: 1, role: role, scheme: organization.scheme })
    { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
  end

  # A finished interview session with a generated portfolio.
  # skills: [{ label: 'React', level: 3, skill_id: nil }]
  def create_portfolio(organization, skills: [{ label: 'React', level: 3 }], status: 'complete')
    assessment = Assessment.create!(
      tenant_id: organization.id, created_by: 1, name: "#{organization.name} role", time_limit_min: 30
    )
    session   = Session.create!(tenant_id: organization.id, assessment: assessment)
    portfolio = session.create_portfolio!(generation_status: status)

    skills.each do |skill|
      portfolio.portfolio_skills.create!(
        skill_id:           skill[:skill_id],
        skill_label:        skill[:label],
        ai_level:           skill[:level],
        ai_confidence:      skill.fetch(:confidence, 'high'),
        competency_summary: "Summary for #{skill[:label]}",
        evidence:           ['A revealing quote']
      )
    end

    portfolio
  end

  # skills: [{ label: 'React', level: 3, skill_id: nil }]
  def create_vacancy(organization, role_title: 'Backend Engineer', skills: [{ label: 'React', level: 3 }])
    vacancy = Vacancy.create!(tenant_id: organization.id, created_by: 1, role_title: role_title)
    skills.each do |skill|
      vacancy.vacancy_skills.create!(
        skill_id: skill[:skill_id], skill_label: skill[:label], expected_level: skill[:level]
      )
    end
    vacancy
  end

  # A finished interview: an assessment with configured skills, a session whose
  # coverage map says how deeply each skill was actually discussed, and a transcript.
  # skills: [{ id: 'sk-react', label: 'React', state: 'covered', probes: 3 }]
  def create_interview(organization, skills:, discovered: [])
    assessment = Assessment.create!(
      tenant_id: organization.id, created_by: 1, name: 'Frontend role', time_limit_min: 30
    )
    skills.each_with_index do |skill, index|
      assessment.assessment_skills.create!(
        skill_id: skill[:id], skill_label: skill[:label], display_order: index,
        l1_anchor: 'L1 anchor', l2_anchor: 'L2 anchor', l3_anchor: 'L3 anchor',
        l4_anchor: 'L4 anchor', l5_anchor: 'L5 anchor'
      )
    end

    session = Session.create!(
      tenant_id: organization.id, assessment: assessment, status: 'ended', end_reason: 'manual_assessor'
    )
    skills.each do |skill|
      session.coverage_maps.create!(
        skill_id: skill[:id], skill_label: skill[:label], is_discovered: false,
        state: skill[:state], probe_count: skill[:probes]
      )
    end
    discovered.each do |skill|
      session.coverage_maps.create!(
        skill_id: nil, skill_label: skill[:label], is_discovered: true,
        state: skill[:state], probe_count: skill[:probes]
      )
    end
    session.transcript_turns.create!(turn_number: 1, speaker: 'candidate', text: 'I mostly work with React.')
    session
  end
end
