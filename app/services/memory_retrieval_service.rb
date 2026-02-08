class MemoryRetrievalService
  DEFAULT_WEIGHTS = { recency: 0.3, importance: 0.3, relevance: 0.4 }.freeze
  DECAY_RATE = 0.01
  CANDIDATE_LIMIT = 200

  # --- Primary retrieval: scored by recency + importance + relevance ---

  def self.get_relevant_memories(agent:, query: nil, limit: 10, weights: DEFAULT_WEIGHTS)
    current_tick = SimulationService.current_tick
    candidates = fetch_candidates(agent, query)
    return [] if candidates.empty?

    # Extract raw relevance scores and normalize to 0-1 range
    raw_scores = candidates.map do |memory|
      memory.respond_to?(:rank) && memory.rank ? memory.rank.to_f : 0.0
    end
    max_rank = raw_scores.max
    max_rank = nil if max_rank && max_rank < 1e-10 # treat near-zero as no relevance

    scored = candidates.each_with_index.map do |memory, i|
      relevance_val = max_rank ? raw_scores[i] / max_rank : 0.0

      score = (weights[:recency] * recency_score(memory.tick, current_tick)) +
              (weights[:importance] * importance_score(memory.importance)) +
              (weights[:relevance] * relevance_val)

      [ memory, score ]
    end

    scored.sort_by { |_, s| -s }.first(limit).map(&:first)
  end

  # --- Helper queries ---

  def self.get_recent_memories(agent:, limit: 20)
    MemoryService.memories_for(agent: agent, limit: limit)
  end

  def self.get_memories_about_agent(agent:, target_agent_id:, limit: 10)
    agent.memories.about_agent(target_agent_id).recent.limit(limit)
  end

  def self.get_memories_at_location(agent:, location:, limit: 10)
    location_id = location.respond_to?(:id) ? location.id : location
    agent.memories.where(location_id: location_id).recent.limit(limit)
  end

  # --- Scoring functions ---

  def self.recency_score(memory_tick, current_tick)
    ticks_ago = [ current_tick - memory_tick, 0 ].max
    Math.exp(-DECAY_RATE * ticks_ago)
  end
  private_class_method :recency_score

  def self.importance_score(importance)
    (importance - 1) / 9.0
  end
  private_class_method :importance_score

  # --- Candidate fetching ---

  def self.fetch_candidates(agent, query)
    if query.present?
      sanitized = ActiveRecord::Base.connection.quote(query)
      agent.memories
           .select("memories.*, ts_rank(search_vector, plainto_tsquery('english', #{sanitized})) AS rank")
           .order(Arel.sql("rank DESC, tick DESC"))
           .limit(CANDIDATE_LIMIT)
    else
      agent.memories.recent.limit(CANDIDATE_LIMIT)
    end
  end
  private_class_method :fetch_candidates
end
