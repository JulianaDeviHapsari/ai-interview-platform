# frozen_string_literal: true

class Portfolio < ApplicationRecord
  GENERATION_STATUSES = %w[pending generating complete failed].freeze

  belongs_to :session
  has_many :portfolio_skills, dependent: :destroy
  has_many :assessor_overrides, through: :portfolio_skills

  validates :generation_status, inclusion: { in: GENERATION_STATUSES }

  scope :complete,    -> { where(generation_status: 'complete') }
  scope :failed,      -> { where(generation_status: 'failed') }
  scope :generating,  -> { where(generation_status: 'generating') }

  # Portfolios have no tenant_id of their own: they belong to an organization
  # through their session. Always look portfolios up through this scope when
  # the id comes from a request, never with Portfolio.find.
  scope :for_tenant, ->(tenant_id) { joins(:session).where(sessions: { tenant_id: tenant_id }) }

  # A job that dies hard (worker killed, deploy) can leave a portfolio in
  # "generating" forever. After this long we treat it as stopped.
  GENERATION_TIMEOUT = 10.minutes
  STALE_MESSAGE = 'Generation took too long and was stopped. Please retry.'

  def complete?    = generation_status == 'complete'
  def generating?  = generation_status == 'generating'
  def failed?      = generation_status == 'failed'

  def stale_generating?
    generating? && (generation_started_at.nil? || generation_started_at < GENERATION_TIMEOUT.ago)
  end

  # What the API reports: a stale "generating" is shown as failed.
  def display_status
    stale_generating? ? 'failed' : generation_status
  end

  def display_error
    stale_generating? ? STALE_MESSAGE : generation_error
  end

  # Skills the assessor configured for the interview that the AI could not
  # judge (never discussed). Shown as "not assessed" instead of a made-up level.
  def unassessed_skills
    configured = session.assessment&.assessment_skills.to_a
    assessed = portfolio_skills.reject(&:is_discovered)
    ids    = assessed.map(&:skill_id).compact
    labels = assessed.map { |s| s.skill_label.to_s.downcase }

    configured.reject do |skill|
      ids.include?(skill.skill_id) || labels.include?(skill.skill_label.to_s.downcase)
    end
  end
end
