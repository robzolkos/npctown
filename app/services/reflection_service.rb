class ReflectionService
  REFLECTION_INTERVAL = 100
  UNREFLECTED_LIMIT = 20
  MIN_OBSERVATIONS = 5
  PLATFORM_IMPORTANCE = 7
  PATTERN_THRESHOLD = 3
  MAX_REFLECTIONS_PER_CYCLE = 2

  # --- Tick listener interface ---

  def self.on_tick(tick)
    return unless tick > 0 && (tick % REFLECTION_INTERVAL).zero?

    ProcessReflectionsJob.perform_async(tick)
  end

  def self.name
    "ReflectionService"
  end

  # --- Processing (called by ProcessReflectionsJob) ---

  def self.generate_reflections(tick)
    Agent.active.find_each do |agent|
      reflect_for_agent(agent: agent, tick: tick)
    end
  end

  def self.reflect_for_agent(agent:, tick:)
    observations = agent.memories.observations.unreflected.by_importance.limit(UNREFLECTED_LIMIT)
    return if observations.size < MIN_OBSERVATIONS

    reflections = []
    reflections.concat(detect_location_patterns(observations))
    reflections.concat(detect_agent_interaction_patterns(observations))
    reflections = reflections.first(MAX_REFLECTIONS_PER_CYCLE)

    return if reflections.empty?

    reflections.each do |content|
      memory = MemoryService.create_memory(
        agent: agent,
        type: "reflection",
        content: content,
        importance: PLATFORM_IMPORTANCE,
        tick: tick,
        location: agent.location
      )

      EventService.append(
        event_type: "reflection_created",
        tick: tick,
        agent: agent,
        location: agent.location,
        payload: { memory_id: memory.id, content: content, source: "system" }
      )
    end

    observations.update_all(reflected_upon: true)
  end

  # --- Pattern Detection ---

  def self.detect_location_patterns(observations)
    location_counts = Hash.new(0)
    observations.each { |obs| location_counts[obs.location_id] += 1 if obs.location_id }

    location_counts.select { |_, count| count >= PATTERN_THRESHOLD }
                   .sort_by { |_, count| -count }
                   .first(1)
                   .filter_map do |location_id, _|
      location = Location.find_by(id: location_id)
      next unless location

      "I've been spending a lot of time at the #{location.name}."
    end
  end
  private_class_method :detect_location_patterns

  def self.detect_agent_interaction_patterns(observations)
    agent_counts = Hash.new(0)
    observations.each do |obs|
      (obs.related_agent_ids || []).each { |aid| agent_counts[aid] += 1 }
    end

    agent_counts.select { |_, count| count >= PATTERN_THRESHOLD }
                .sort_by { |_, count| -count }
                .first(1)
                .filter_map do |agent_id, _|
      other = Agent.find_by(id: agent_id)
      next unless other

      "I've been interacting with #{other.name} quite a bit."
    end
  end
  private_class_method :detect_agent_interaction_patterns
end
