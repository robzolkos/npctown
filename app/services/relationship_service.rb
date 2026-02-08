class RelationshipService
  class RelationshipError < StandardError; end

  def self.find_or_create(agent:, target_agent:)
    Relationship.find_or_create_by!(agent: agent, target_agent: target_agent)
  end

  def self.on_conversation_started(initiator:, target_agent:, tick:)
    update_both(initiator, target_agent, tick, familiarity: 3, trust: 1)
  end

  def self.on_conversation_message(speaker:, other_participants:, tick:)
    other_participants.each do |other|
      update_both(speaker, other, tick, familiarity: 1, trust: 1)
    end
  end

  def self.relationships_for(agent:)
    Relationship.for_agent(agent).where("familiarity >= ?", 10)
  end

  # --- Private ---

  def self.update_both(agent_a, agent_b, tick, deltas)
    update_one(agent: agent_a, target_agent: agent_b, tick: tick, **deltas)
    update_one(agent: agent_b, target_agent: agent_a, tick: tick, **deltas)
  end
  private_class_method :update_both

  def self.update_one(agent:, target_agent:, tick:, **deltas)
    rel = find_or_create(agent: agent, target_agent: target_agent)

    rel.trust = (rel.trust + (deltas[:trust] || 0)).clamp(-100, 100)
    rel.affection = (rel.affection + (deltas[:affection] || 0)).clamp(-100, 100)
    rel.respect = (rel.respect + (deltas[:respect] || 0)).clamp(-100, 100)
    rel.familiarity = (rel.familiarity + (deltas[:familiarity] || 0)).clamp(0, 100)
    rel.last_interaction_tick = tick
    rel.save!

    emit_event(agent: agent, target_agent: target_agent, relationship: rel, tick: tick)
  end
  private_class_method :update_one

  def self.emit_event(agent:, target_agent:, relationship:, tick:)
    EventService.append(
      event_type: "relationship_changed",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: {
        target_agent_id: target_agent.id,
        target_agent_name: target_agent.name,
        trust: relationship.trust,
        affection: relationship.affection,
        respect: relationship.respect,
        familiarity: relationship.familiarity,
        label: relationship.label
      }
    )
  end
  private_class_method :emit_event
end
