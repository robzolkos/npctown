class PerceptionService
  BASE_ACTIONS = %w[move speak emote wait startConversation joinConversation leaveConversation conversationMessage].freeze
  REFLECT_THRESHOLD = 5

  def self.build(agent)
    location = agent.location
    tick = SimulationService.current_tick

    {
      tick: tick,
      location: location_json(location),
      nearbyAgents: nearby_agents(agent, location),
      activeConversations: active_conversations(location),
      recentEvents: recent_events(location, tick),
      recentMemories: recent_memories(agent, tick),
      relevantMemories: relevant_memories(agent, location),
      recentReflections: recent_reflections(agent),
      unreflectedObservations: unreflected_observations(agent),
      self: self_json(agent),
      availableActions: available_actions(agent),
      allLocations: all_locations
    }
  end

  def self.location_json(location)
    {
      id: location.id,
      name: location.name,
      description: location.description
    }
  end
  private_class_method :location_json

  def self.nearby_agents(agent, location)
    Agent.at_location(location).where.not(id: agent.id).map do |a|
      {
        id: a.id,
        name: a.name,
        description: a.description,
        personalityTraits: a.personality_traits,
        status: a.status
      }
    end
  end
  private_class_method :nearby_agents

  def self.active_conversations(location)
    Conversation.active.at_location(location)
                .includes(conversation_participants: :agent, conversation_messages: :agent)
                .map do |conv|
      {
        id: conv.id,
        participants: conv.agents.map { |a| { id: a.id, name: a.name } },
        recentMessages: conv.conversation_messages.order(tick: :desc, created_at: :desc).limit(5)
                           .reverse.map do |msg|
          {
            agentId: msg.agent_id,
            agentName: msg.agent.name,
            content: msg.content,
            tick: msg.tick
          }
        end
      }
    end
  end
  private_class_method :active_conversations

  def self.recent_events(location, tick)
    since_tick = [ tick - 10, 0 ].max
    EventService.at_location(location, since_tick: since_tick).map do |event|
      {
        id: event.id,
        type: event.event_type,
        tick: event.tick,
        payload: event.payload,
        agentId: event.agent_id
      }
    end
  end
  private_class_method :recent_events

  def self.recent_memories(agent, tick)
    since_tick = [ tick - 10, 0 ].max
    MemoryService.memories_for(agent: agent, since_tick: since_tick, limit: 20).map do |m|
      {
        id: m.id,
        type: m.memory_type,
        content: m.content,
        importance: m.importance,
        tick: m.tick
      }
    end
  end
  private_class_method :recent_memories

  def self.relevant_memories(agent, location)
    nearby_names = Agent.at_location(location).where.not(id: agent.id).pluck(:name)
    query = [ location.name, *nearby_names ].join(" ")

    MemoryRetrievalService.get_relevant_memories(agent: agent, query: query, limit: 5).map do |m|
      {
        id: m.id,
        type: m.memory_type,
        content: m.content,
        importance: m.importance,
        tick: m.tick
      }
    end
  end
  private_class_method :relevant_memories

  def self.recent_reflections(agent)
    agent.memories.reflection_type.recent.limit(5).map do |m|
      {
        id: m.id,
        content: m.content,
        importance: m.importance,
        tick: m.tick
      }
    end
  end
  private_class_method :recent_reflections

  def self.unreflected_observations(agent)
    observations = agent.memories.observations.unreflected.by_importance.limit(20)
    {
      count: agent.memories.observations.unreflected.count,
      memories: observations.map do |m|
        { id: m.id, content: m.content, importance: m.importance, tick: m.tick }
      end
    }
  end
  private_class_method :unreflected_observations

  def self.available_actions(agent)
    actions = BASE_ACTIONS.dup
    actions << "reflect" if agent.memories.observations.unreflected.count >= REFLECT_THRESHOLD
    actions
  end
  private_class_method :available_actions

  def self.self_json(agent)
    {
      id: agent.id,
      name: agent.name,
      status: agent.status,
      stamina: agent.stamina,
      food: agent.food,
      energy: agent.energy,
      currency: agent.currency
    }
  end
  private_class_method :self_json

  def self.all_locations
    Location.left_joins(:agents).group(:id).select("locations.*, COUNT(agents.id) AS agent_count").map do |loc|
      {
        id: loc.id,
        name: loc.name,
        description: loc.description,
        agentCount: loc.agent_count
      }
    end
  end
  private_class_method :all_locations
end
