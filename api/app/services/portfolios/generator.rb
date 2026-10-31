# frozen_string_literal: true

module Portfolios
  # N10: Generates a structured skill portfolio from the full transcript
  # and final coverage map using Gemini Pro.
  # Runs post-session as a background job.
  class Generator
    def initialize(session:, gemini_client: nil)
      @session = session
      @gemini_client = gemini_client || Gemini::HttpClient.new(
        model:   ENV.fetch('GEMINI_PRO_MODEL', 'gemini-2.0-pro-001'),
        timeout: 180  # up to 3 minutes for large transcripts
      )
    end

    # The model answered, but not with the JSON object we asked for.
    class InvalidResponse < StandardError; end

    # Returns the Portfolio record with skills populated.
    def call
      portfolio = @session.portfolio || @session.create_portfolio!(
        candidate_id:      @session.candidate_id,
        generation_status: 'pending'
      )

      # Duplicate or late jobs must not run the model again (cost) or overwrite
      # a finished portfolio.
      return portfolio unless claim(portfolio)

      prompt   = build_prompt
      response = @gemini_client.generate_content(prompt, temperature: 0.2)

      save_skills(portfolio, response)
      portfolio.update!(generation_status: 'complete', generated_at: Time.current, generation_error: nil)

      Rails.logger.info("[N10] Portfolio generated for session #{@session.id}")
      portfolio
    rescue => e
      # Store and log the exception CLASS only. Messages can quote model output,
      # which can contain what the candidate said.
      portfolio&.update!(generation_status: 'failed', generation_error: FailureReason.for(e.class.name))
      Rails.logger.error("[N10] Portfolio generation failed for session #{@session.id}: #{e.class}")
      raise
    end

    private

    def build_prompt
      assessment       = @session.assessment
      configured_skills = assessment.assessment_skills.order(:display_order)
      coverage_maps     = @session.coverage_maps.order(:id)
      turns             = @session.transcript_turns.ordered

      skills_text = configured_skills.map { |s| skill_definition_block(s) }.join("\n\n")

      coverage_json = {
        skills:     coverage_maps.reject(&:is_discovered).map { |m| coverage_json(m) },
        discovered: coverage_maps.select(&:is_discovered).map { |m| coverage_json(m) }
      }.to_json

      transcript_text = turns.map { |t| "[#{t.speaker.upcase}]: #{t.text}" }.join("\n")

      <<~PROMPT
        You are evaluating a completed skills assessment interview to produce a structured skill portfolio.

        ROLE BEING ASSESSED: #{assessment.name}

        SKILL DEFINITIONS AND BEHAVIORAL ANCHORS:
        #{skills_text}

        UNIVERSAL L1-L5 ANCHORS (use for discovered skills):
        L1 — Executes with explicit guidance and close review. Understands conceptually but cannot apply independently.
        L2 — Executes independently on routine scope. Uses known patterns. Handles common cases but not edge cases.
        L3 — Executes complex, ambiguous scope. Makes tradeoffs. Handles edge cases. Can teach L1-L2.
        L4 — Defines standards and creates reusable systems. Resolves systemic problems. Cross-team impact.
        L5 — Org-level authority. Shapes how the skill is practiced. Rare.

        FINAL COVERAGE MAP:
        #{coverage_json}

        FULL INTERVIEW TRANSCRIPT:
        #{transcript_text}

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        TASK
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        For EACH skill in the coverage map (both configured and discovered):

        1. FIND THE EVIDENCE
           Read all transcript turns where this skill was discussed.
           Identify the 2-3 most revealing quotes from the CANDIDATE (not the AI).
           A quote is revealing if it shows HOW they think, not just WHAT they know.

        2. ASSIGN A LEVEL
           Compare the candidate's actual behavior to the L1-L5 anchors.
           Assign the highest level where you see CONSISTENT evidence, not just one strong moment.
           If evidence is mixed (mostly L2 with one L3 moment), assign L2.

        3. WRITE THE COMPETENCY SUMMARY
           2-3 sentences. Focus on patterns, not individual answers.
           What does this person reliably do at this skill? What's the ceiling? What's missing?

        4. ASSIGN CONFIDENCE
           high — probe_count >= 3 AND state = covered
           medium — probe_count = 2 OR state = partial
           low — probe_count <= 1 OR state = initiated

        OUTPUT (JSON only, no prose):
        {
          "configured_skills": [
            {
              "skill_id": "sk-eng-001",
              "skill_label": "React / Frontend Development",
              "level": 3,
              "confidence": "high",
              "evidence": ["quote 1", "quote 2", "quote 3"],
              "competency_summary": "2-3 sentence summary"
            }
          ],
          "discovered_skills": [
            {
              "skill_label": "Micro-frontend Architecture",
              "level": 2,
              "confidence": "low",
              "evidence": ["quote 1"],
              "competency_summary": "2-3 sentence summary"
            }
          ]
        }
      PROMPT
    end

    def skill_definition_block(skill)
      lines = ["━━━━━━━━━━━━━━━"]
      lines << "SKILL: #{skill.skill_label} (#{skill.skill_id || 'custom'})"
      lines << "SCOPE: #{skill.scope_include}" if skill.scope_include.present?
      lines << ""
      lines << "L1 — #{skill.l1_anchor}"
      lines << "L2 — #{skill.l2_anchor}"
      lines << "L3 — #{skill.l3_anchor}"
      lines << "L4 — #{skill.l4_anchor}"
      lines << "L5 — #{skill.l5_anchor}"
      lines.join("\n")
    end

    def coverage_json(map)
      {
        id:          map.skill_id || map.skill_label.downcase.gsub(/\s+/, '-'),
        label:       map.skill_label,
        state:       map.state,
        probe_count: map.probe_count,
        is_discovered: map.is_discovered
      }
    end

    # Marks the portfolio as being generated by this run. Returns false when there
    # is nothing to do: it is already complete, or another run is still working.
    def claim(portfolio)
      portfolio.with_lock do
        next false if portfolio.complete?
        next false if portfolio.generating? && !portfolio.stale_generating?

        portfolio.update!(generation_status: 'generating', generation_started_at: Time.current, generation_error: nil)
        true
      end
    end

    def save_skills(portfolio, response)
      data = response.is_a?(String) ? JSON.parse(response) : response
      raise InvalidResponse, 'model answer is not a JSON object' unless data.is_a?(Hash)

      coverage_maps = @session.coverage_maps.to_a

      # All or nothing: a failure half-way must not leave a partial portfolio.
      # requires_new makes this a real (savepoint) transaction even when the
      # caller is already inside one, so the rollback always happens.
      ActiveRecord::Base.transaction(requires_new: true) do
        portfolio.portfolio_skills.destroy_all

        entries(data, 'configured_skills').each { |entry| save_skill(portfolio, entry, coverage_maps, discovered: false) }
        entries(data, 'discovered_skills').each { |entry| save_skill(portfolio, entry, coverage_maps, discovered: true) }
      end
    end

    def entries(data, key)
      list = data[key]
      list.is_a?(Array) ? list.select { |entry| entry.is_a?(Hash) } : []
    end

    def save_skill(portfolio, entry, coverage_maps, discovered:)
      coverage = find_coverage(coverage_maps, entry, discovered)

      # Never discussed in the interview: there is no evidence to rate. It stays
      # "not assessed" rather than getting a made-up level.
      return if coverage&.state == 'not_yet'

      level = parse_level(entry['level'])
      if level.nil?
        Rails.logger.warn("[N10] Skipped a skill with no usable level (session #{@session.id})")
        return
      end

      portfolio.portfolio_skills.create!(
        skill_id:           discovered ? nil : (coverage&.skill_id || entry['skill_id']),
        skill_label:        coverage&.skill_label || entry['skill_label'],
        is_discovered:      discovered,
        ai_level:           level,
        ai_confidence:      Confidence.for(coverage),
        evidence:           Array(entry['evidence']).first(3),
        competency_summary: entry['competency_summary']
      )
    end

    def find_coverage(coverage_maps, entry, discovered)
      label = entry['skill_label'].to_s

      if discovered
        coverage_maps.find { |m| m.is_discovered && m.skill_label.casecmp?(label) }
      else
        skill_id = entry['skill_id'].to_s
        coverage_maps.find do |m|
          !m.is_discovered && ((skill_id.present? && m.skill_id == skill_id) || m.skill_label.casecmp?(label))
        end
      end
    end

    # 1..5 as a number or as text such as "3" or "L3". Anything else is not a rating.
    def parse_level(raw)
      level = raw.is_a?(String) ? raw[/\A\s*L?\s*([1-5])\s*\z/i, 1]&.to_i : raw
      level if level.is_a?(Integer) && level.between?(1, 5)
    end
  end
end
