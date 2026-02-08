class ActionService
  class ActionError < StandardError; end

  ACTION_TYPES = %w[move speak emote wait].freeze

  STAMINA_COSTS = {
    "move" => 5,
    "speak" => 1,
    "emote" => 1,
    "wait" => 0
  }.freeze

  def self.execute(agent:, action_type:, params: {})
    validate!(agent, action_type, params)

    tick = SimulationService.current_tick
    cost = STAMINA_COSTS[action_type]

    ActiveRecord::Base.transaction do
      deduct_stamina!(agent, cost, tick) if cost > 0

      event = case action_type
      when "move"  then execute_move(agent, params, tick)
      when "speak" then execute_speak(agent, params, tick)
      when "emote" then execute_emote(agent, params, tick)
      when "wait"  then nil
      end

      { success: true, tick: tick, event: event&.as_json }
    end
  end

  def self.validate!(agent, action_type, params)
    raise ActionError, "Unknown action type: #{action_type}" unless ACTION_TYPES.include?(action_type)
    raise ActionError, "Agent is not active" unless agent.status == "active"

    cost = STAMINA_COSTS[action_type]
    raise ActionError, "Insufficient stamina" if agent.stamina < cost

    case action_type
    when "move"
      raise ActionError, "targetLocationId is required" unless params[:target_location_id].present?
    when "speak"
      raise ActionError, "message is required" unless params[:message].present?
    when "emote"
      raise ActionError, "description is required" unless params[:description].present?
    end
  end
  private_class_method :validate!

  def self.deduct_stamina!(agent, cost, tick)
    previous = agent.stamina
    agent.update!(stamina: previous - cost)

    EventService.append(
      event_type: "stamina_changed",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: {
        previous: previous,
        current: agent.stamina,
        cost: cost,
        reason: "action"
      }
    )
  end
  private_class_method :deduct_stamina!

  def self.execute_move(agent, params, tick)
    location = Location.find_by_prefixed_id(params[:target_location_id])
    raise ActionError, "Location not found" unless location

    WorldService.move_agent(agent: agent, location: location, tick: tick)
  end
  private_class_method :execute_move

  def self.execute_speak(agent, params, tick)
    EventService.append(
      event_type: "agent_spoke",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: { message: params[:message] }
    )
  end
  private_class_method :execute_speak

  def self.execute_emote(agent, params, tick)
    EventService.append(
      event_type: "agent_action",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: { type: "emote", description: params[:description] }
    )
  end
  private_class_method :execute_emote
end
