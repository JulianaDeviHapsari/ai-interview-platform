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
end
