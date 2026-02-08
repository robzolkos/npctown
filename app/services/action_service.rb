class ActionService
  class ActionError < StandardError; end

  ACTION_TYPES = %w[move speak emote wait startConversation joinConversation leaveConversation conversationMessage].freeze

  STAMINA_COSTS = {
    "move" => 5,
    "speak" => 1,
    "emote" => 1,
    "wait" => 0,
    "startConversation" => 2,
    "joinConversation" => 1,
    "leaveConversation" => 0,
    "conversationMessage" => 1
  }.freeze

  def self.execute(agent:, action_type:, params: {})
    validate!(agent, action_type, params)

    tick = SimulationService.current_tick
    cost = STAMINA_COSTS[action_type]

    ActiveRecord::Base.transaction do
      deduct_stamina!(agent, cost, tick) if cost > 0

      event = case action_type
      when "move"                 then execute_move(agent, params, tick)
      when "speak"                then execute_speak(agent, params, tick)
      when "emote"                then execute_emote(agent, params, tick)
      when "wait"                 then nil
      when "startConversation"    then execute_start_conversation(agent, params, tick)
      when "joinConversation"     then execute_join_conversation(agent, params, tick)
      when "leaveConversation"    then execute_leave_conversation(agent, params, tick)
      when "conversationMessage"  then execute_conversation_message(agent, params, tick)
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
    when "startConversation"
      raise ActionError, "targetAgentId is required" unless params[:target_agent_id].present?
      raise ActionError, "message is required" unless params[:message].present?
    when "joinConversation"
      raise ActionError, "conversationId is required" unless params[:conversation_id].present?
    when "leaveConversation"
      raise ActionError, "conversationId is required" unless params[:conversation_id].present?
    when "conversationMessage"
      raise ActionError, "conversationId is required" unless params[:conversation_id].present?
      raise ActionError, "message is required" unless params[:message].present?
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

    # Auto-leave active conversations when moving
    agent.conversation_participants.joins(:conversation)
         .where(conversations: { status: "active" }, left_at_tick: nil)
         .find_each do |cp|
      ConversationService.leave_conversation(conversation: cp.conversation, agent: agent, tick: tick)
    end

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

  def self.execute_start_conversation(agent, params, tick)
    target = Agent.find_by_prefixed_id(params[:target_agent_id])
    raise ActionError, "Target agent not found" unless target

    conversation = ConversationService.start_conversation(
      initiator: agent,
      target_agent: target,
      message: params[:message],
      tick: tick
    )

    # Return the conversation_started event
    Event.where(event_type: "conversation_started").order(created_at: :desc).first
  end
  private_class_method :execute_start_conversation

  def self.execute_join_conversation(agent, params, tick)
    conversation = Conversation.find_by_prefixed_id(params[:conversation_id])
    raise ActionError, "Conversation not found" unless conversation

    ConversationService.join_conversation(conversation: conversation, agent: agent, tick: tick)

    Event.where(event_type: "conversation_message", agent: agent).order(created_at: :desc).first
  end
  private_class_method :execute_join_conversation

  def self.execute_leave_conversation(agent, params, tick)
    conversation = Conversation.find_by_prefixed_id(params[:conversation_id])
    raise ActionError, "Conversation not found" unless conversation

    ConversationService.leave_conversation(conversation: conversation, agent: agent, tick: tick)

    Event.where(event_type: "conversation_message", agent: agent).order(created_at: :desc).first
  end
  private_class_method :execute_leave_conversation

  def self.execute_conversation_message(agent, params, tick)
    conversation = Conversation.find_by_prefixed_id(params[:conversation_id])
    raise ActionError, "Conversation not found" unless conversation

    ConversationService.add_message(conversation: conversation, agent: agent, content: params[:message], tick: tick)

    Event.where(event_type: "conversation_message", agent: agent).order(created_at: :desc).first
  end
  private_class_method :execute_conversation_message
end
