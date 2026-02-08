class SpectatorEventFormatter
  HIDDEN_TYPES = %w[tick_advanced memory_created reflection_created stamina_changed].freeze
  SPECTATOR_TYPES = (Event::TYPES - HIDDEN_TYPES).freeze

  def self.spectator_visible?(event)
    SPECTATOR_TYPES.include?(event.event_type)
  end

  def self.format(event)
    {
      id: event.id,
      tick: event.tick,
      timestamp: event.created_at.iso8601,
      type: event.event_type,
      message: human_message(event),
      details: event.payload || {}
    }
  end

  def self.format_many(events)
    # Batch-load agents to avoid N+1
    agent_ids = events.filter_map(&:agent_id).uniq
    agent_ids += events.filter_map { |e| e.payload&.dig("target_agent_id") }.uniq
    agents = Agent.where(id: agent_ids.compact.uniq).index_by(&:id)

    events.filter_map do |event|
      next unless spectator_visible?(event)

      {
        id: event.id,
        tick: event.tick,
        timestamp: event.created_at.iso8601,
        type: event.event_type,
        message: human_message(event, agents: agents),
        details: event.payload || {}
      }
    end
  end

  def self.human_message(event, agents: {})
    agent_name = resolve_name(event.agent_id, agents, event)
    payload = event.payload || {}

    case event.event_type
    when "agent_registered"
      "#{payload['agent_name'] || agent_name} joined the town"
    when "agent_moved"
      to = payload["to_location_name"] || "somewhere"
      "#{agent_name} moved to #{to}"
    when "agent_spoke"
      "#{agent_name}: \"#{payload['message']}\""
    when "agent_action"
      if payload["type"] == "emote"
        "#{agent_name} #{payload['description']}"
      else
        "#{agent_name} performed an action"
      end
    when "conversation_started"
      target_name = resolve_name(payload["target_agent_id"], agents)
      "#{agent_name} started a conversation with #{target_name}"
    when "conversation_message"
      if payload["system"]
        payload["message"]
      else
        "#{agent_name} (in conversation): \"#{payload['message']}\""
      end
    when "conversation_ended"
      "A conversation ended (#{payload['reason'] || 'unknown'})"
    when "relationship_changed"
      target_name = resolve_name(payload["target_agent_id"], agents)
      "#{agent_name}'s relationship with #{target_name} changed"
    when "resource_changed"
      resource_message(agent_name, payload, agents)
    when "plan_created"
      "#{agent_name} made a plan: #{payload['goal']}"
    when "plan_updated"
      "#{agent_name} updated their plan"
    when "plan_completed"
      "#{agent_name} completed their plan: #{payload['goal']}"
    when "plan_abandoned"
      "#{agent_name} abandoned their plan"
    else
      "Something happened"
    end
  end

  # --- Private ---

  def self.resolve_name(agent_id, agents, event = nil)
    return "Someone" unless agent_id

    cached = agents[agent_id]
    return cached.name if cached

    event&.agent&.name || Agent.find_by(id: agent_id)&.name || "Someone"
  end
  private_class_method :resolve_name

  def self.resource_message(agent_name, payload, agents)
    case payload["reason"]
    when "rest"
      "#{agent_name} rested and recovered energy"
    when "eat"
      "#{agent_name} ate some food"
    when "trade"
      target_name = resolve_name(payload["target_agent_id"], agents)
      "#{agent_name} traded #{payload['amount']} #{payload['resource']} with #{target_name}"
    when "market_bonus"
      "#{agent_name} earned resources from the Market"
    else
      "#{agent_name}'s resources changed"
    end
  end
  private_class_method :resource_message
end
