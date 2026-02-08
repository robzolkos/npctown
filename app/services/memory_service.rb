class MemoryService
  class MemoryError < StandardError; end

  REDIS_KEY_PREFIX = "npctown:memory_service"
  LAST_TICK_KEY = "#{REDIS_KEY_PREFIX}:last_processed_tick"
  LOCK_KEY = "#{REDIS_KEY_PREFIX}:processing_lock"
  LOCK_TTL = 30
  MAX_MEMORIES_PER_AGENT = 1000

  IMPORTANCE_MAP = {
    "agent_moved"           => 2,
    "stamina_changed"       => 2,
    "resource_changed"      => 3,
    "agent_action"          => 3,
    "agent_spoke"           => 4,
    "conversation_started"  => 5,
    "conversation_message"  => 5,
    "conversation_ended"    => 6,
    "agent_registered"      => 7,
    "relationship_changed"  => 7,
    "plan_created"          => 5,
    "plan_updated"          => 3,
    "plan_completed"        => 6,
    "plan_abandoned"        => 4
  }.freeze

  SKIP_EVENT_TYPES = %w[tick_advanced memory_created reflection_created].freeze

  SELF_IMPORTANCE_DISCOUNT = 1

  # --- Redis key scoping (for parallel test isolation) ---

  @redis_key_prefix = nil

  class << self
    attr_writer :redis_key_prefix

    def redis_key_prefix
      @redis_key_prefix || REDIS_KEY_PREFIX
    end
  end

  # --- State (Redis-backed, survives restarts, shared across processes) ---

  def self.last_processed_tick
    val = Sidekiq.redis { |conn| conn.get("#{redis_key_prefix}:last_processed_tick") }
    val ? val.to_i : -1
  end

  def self.last_processed_tick=(tick)
    Sidekiq.redis { |conn| conn.set("#{redis_key_prefix}:last_processed_tick", tick.to_s) }
  end

  # --- Public API ---

  def self.create_memory(agent:, type: "observation", content:, importance:, tick:, location: nil, related_agent_ids: [])
    Memory.create!(
      agent: agent,
      memory_type: type,
      content: content,
      importance: importance.clamp(1, 10),
      tick: tick,
      location: location,
      related_agent_ids: related_agent_ids
    )
  end

  def self.observe_event(event:, agent:, agent_cache: {})
    return nil if SKIP_EVENT_TYPES.include?(event.event_type)

    content = describe_event(event, agent, agent_cache)
    return nil if content.blank?

    base_importance = IMPORTANCE_MAP.fetch(event.event_type, 3)
    importance = if event.agent_id == agent.id
                   [ base_importance - SELF_IMPORTANCE_DISCOUNT, 1 ].max
    else
                   base_importance
    end

    related_ids = extract_related_agent_ids(event, agent)

    create_memory(
      agent: agent,
      content: content,
      importance: importance,
      tick: event.tick,
      location: event.location,
      related_agent_ids: related_ids
    )
  end

  def self.memories_for(agent:, type: nil, min_importance: nil, since_tick: nil, limit: 50)
    scope = agent.memories.recent
    scope = scope.where(memory_type: type) if type.present?
    scope = scope.where("importance >= ?", min_importance) if min_importance.present?
    scope = scope.where("tick >= ?", since_tick) if since_tick.present?
    scope.limit(limit)
  end

  # Fix #2: Async - enqueue Sidekiq job instead of processing inline
  def self.on_tick(tick)
    ProcessMemoriesJob.perform_async(tick)
  end

  def self.name
    "MemoryService"
  end

  # --- Processing (called by ProcessMemoriesJob) ---

  def self.process_events_into_memories(tick)
    from_tick = last_processed_tick
    lock_key = "#{redis_key_prefix}:processing_lock"

    # Fix #5: Redis lock prevents concurrent processing
    locked = Sidekiq.redis { |conn| conn.set(lock_key, "1", nx: true, ex: LOCK_TTL) }
    return unless locked

    begin
      events = Event.where("tick > ? AND tick < ?", from_tick, tick)
                    .where.not(event_type: SKIP_EVENT_TYPES)
                    .includes(:agent, :location)
                    .chronological

      if events.empty?
        self.last_processed_tick = tick - 1
        return
      end

      # Fix #4: Batch-load target agents referenced in payloads (eliminates N+1)
      target_ids = events.filter_map { |e| e.payload&.dig("target_agent_id") }.uniq
      agent_cache = target_ids.any? ? Agent.where(id: target_ids).index_by(&:id) : {}

      events_by_location = events.group_by(&:location_id)
      affected_agent_ids = Set.new

      events_by_location.each do |location_id, location_events|
        next if location_id.nil?

        # Fix #3: find_each batches agent loading for large locations
        Agent.where(location_id: location_id, status: "active").find_each do |agent|
          location_events.each do |event|
            observe_event(event: event, agent: agent, agent_cache: agent_cache)
          end
          affected_agent_ids << agent.id
        end
      end

      self.last_processed_tick = tick - 1

      # Fix #6: Trim old memories for affected agents
      affected_agent_ids.each { |aid| trim_memories(aid) }
    ensure
      Sidekiq.redis { |conn| conn.del(lock_key) }
    end
  end

  # Fix #6: Cap memories per agent, keeping most important/recent
  def self.trim_memories(agent_id, max: MAX_MEMORIES_PER_AGENT)
    count = Memory.where(agent_id: agent_id).count
    return if count <= max

    overage = count - max
    Memory.where(agent_id: agent_id)
          .order(importance: :asc, tick: :asc)
          .limit(overage)
          .delete_all
  end

  # --- Private ---

  def self.describe_event(event, observer, agent_cache = {})
    agent_name = if event.agent_id == observer.id
                   "You"
    else
                   event.agent&.name || "Someone"
    end
    payload = event.payload || {}

    case event.event_type
    when "agent_moved"
      from = payload["from_location_name"] || "somewhere"
      to = payload["to_location_name"] || "somewhere"
      "#{agent_name} moved from #{from} to #{to}"
    when "agent_spoke"
      "#{agent_name} said: \"#{payload['message']}\""
    when "agent_action"
      if payload["type"] == "emote"
        "#{agent_name} #{payload['description']}"
      else
        "#{agent_name} performed an action"
      end
    when "agent_registered"
      "#{payload['agent_name'] || agent_name} arrived in town"
    when "conversation_started"
      # Fix #4: Use agent_cache instead of N+1 query
      target = agent_cache[payload["target_agent_id"]]
      target_name = target&.name || "someone"
      if event.agent_id == observer.id
        "You started a conversation with #{target_name}"
      else
        "#{agent_name} started a conversation with #{target_name}"
      end
    when "conversation_message"
      if payload["system"]
        payload["message"]
      else
        "#{agent_name} said in conversation: \"#{payload['message']}\""
      end
    when "conversation_ended"
      "A conversation ended (#{payload['reason'] || 'unknown reason'})"
    when "relationship_changed"
      "#{agent_name}'s relationship changed"
    when "resource_changed"
      "#{agent_name}'s resources changed"
    when "stamina_changed"
      if event.agent_id == observer.id
        "You spent energy (stamina: #{payload['previous']} -> #{payload['current']})"
      else
        "#{agent_name} exerted themselves"
      end
    when "plan_created"
      "#{agent_name} formed a plan: #{payload['goal']}"
    when "plan_updated"
      "#{agent_name} updated their plan: #{payload['goal']}"
    when "plan_completed"
      "#{agent_name} completed their plan: #{payload['goal']}"
    when "plan_abandoned"
      reason_note = payload["reason"] == "stale" ? " (abandoned due to inactivity)" : ""
      "#{agent_name} abandoned their plan: #{payload['goal']}#{reason_note}"
    end
  end
  private_class_method :describe_event

  def self.extract_related_agent_ids(event, observer)
    ids = []
    ids << event.agent_id if event.agent_id && event.agent_id != observer.id

    payload = event.payload || {}
    ids << payload["target_agent_id"] if payload["target_agent_id"] && payload["target_agent_id"] != observer.id
    ids << payload["initiator_id"] if payload["initiator_id"] && payload["initiator_id"] != observer.id

    ids.compact.uniq
  end
  private_class_method :extract_related_agent_ids
end
