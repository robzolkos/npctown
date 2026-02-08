class PagesController < ApplicationController
  def home
    render inertia: "Home"
  end

  def feed
    locations = Location.includes(agents: [ :plans, :relationships ]).order(:name).map do |loc|
      {
        id: loc.id,
        name: loc.name,
        type: loc.location_type,
        agents: loc.agents.active.order(:name).map { |a| serialize_agent(a) }
      }
    end

    render inertia: "Feed", props: {
      locations: locations,
      currentTick: Event.maximum(:tick) || 0
    }
  end

  def world
    locations = Location.includes(agents: [ :plans, :relationships ]).order(:name).map do |loc|
      {
        id: loc.id,
        name: loc.name,
        description: loc.description,
        type: loc.location_type,
        agents: loc.agents.active.order(:name).map { |a| serialize_agent(a) },
        active_conversations: loc.conversations.active.count
      }
    end

    render inertia: "World", props: {
      locations: locations,
      currentTick: Event.maximum(:tick) || 0,
      totalAgents: Agent.active.count
    }
  end

  def agent_profile
    agent = Agent.includes(:location, :plans, relationships: :target_agent)
                 .find_by_prefixed_id!(params[:id])

    events = Event.for_agent(agent)
                  .where(event_type: SpectatorEventFormatter::SPECTATOR_TYPES)
                  .recent
                  .limit(50)

    render inertia: "AgentProfile", props: {
      agent: serialize_agent_profile(agent),
      recentEvents: SpectatorEventFormatter.format_many(events),
      currentTick: Event.maximum(:tick) || 0
    }
  end

  def docs
    render inertia: "Docs"
  end

  private

  def serialize_agent_profile(agent)
    {
      id: agent.id,
      name: agent.name,
      description: agent.description,
      personality_traits: agent.personality_traits || [],
      goals: agent.goals || [],
      status: agent.status,
      location_name: agent.location&.name,
      location_id: agent.location_id,
      resource_labels: ResourceService.resource_description(agent),
      stamina_label: stamina_label(agent.stamina),
      current_plan: agent.active_plan&.then { |p| { goal: p.goal, steps: p.steps, status: p.status } },
      relationships: agent.relationships.includes(:target_agent).map { |r|
        {
          target_id: r.target_agent_id,
          target_name: r.target_agent.name,
          trust: r.trust,
          affection: r.affection,
          respect: r.respect,
          familiarity: r.familiarity,
          label: r.label
        }
      },
      reflections: agent.memories.where(memory_type: "reflection").order(tick: :desc).limit(10).map { |m|
        { id: m.id, content: m.content, importance: m.importance, tick: m.tick }
      },
      stats: {
        total_events: agent.events.count,
        total_conversations: agent.conversations.count,
        total_memories: agent.memories.count,
        relationship_count: agent.relationships.count,
        registered_at_tick: agent.events.of_type("agent_registered").pick(:tick)
      }
    }
  end

  def stamina_label(stamina)
    if stamina <= 10 then "exhausted"
    elsif stamina <= 30 then "tired"
    elsif stamina <= 60 then "rested"
    else "energetic"
    end
  end

  def serialize_agent(agent)
    {
      id: agent.id,
      name: agent.name,
      description: agent.description,
      personality_traits: agent.personality_traits || [],
      goals: agent.goals || [],
      stamina: agent.stamina,
      energy: agent.energy,
      food: agent.food,
      currency: agent.currency,
      status: agent.status,
      current_plan: agent.active_plan&.then { |p| { goal: p.goal, steps: p.steps, status: p.status } },
      relationships: agent.relationships.includes(:target_agent).map { |r|
        {
          target_id: r.target_agent_id,
          target_name: r.target_agent.name,
          trust: r.trust,
          affection: r.affection,
          respect: r.respect,
          familiarity: r.familiarity,
          label: r.label
        }
      }
    }
  end
end
