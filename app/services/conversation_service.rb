class ConversationService
  class ConversationError < StandardError; end

  MAX_ACTIVE_CONVERSATIONS = 2
  STALE_THRESHOLD_TICKS = 5

  def self.start_conversation(initiator:, target_agent:, message:, tick:)
    validate_same_location!(initiator, target_agent)
    validate_conversation_limit!(initiator)
    validate_conversation_limit!(target_agent)

    conversation = Conversation.create!(
      location: initiator.location,
      status: "active",
      started_at_tick: tick
    )

    conversation.conversation_participants.create!(agent: initiator, joined_at_tick: tick)
    conversation.conversation_participants.create!(agent: target_agent, joined_at_tick: tick)
    conversation.conversation_messages.create!(agent: initiator, content: message, tick: tick)

    EventService.append(
      event_type: "conversation_started",
      tick: tick,
      agent: initiator,
      location: initiator.location,
      payload: {
        conversation_id: conversation.id,
        initiator_id: initiator.id,
        target_agent_id: target_agent.id,
        message: message
      }
    )

    conversation
  end

  def self.add_message(conversation:, agent:, content:, tick:)
    validate_active!(conversation)
    validate_active_participant!(conversation, agent)

    msg = conversation.conversation_messages.create!(agent: agent, content: content, tick: tick)

    EventService.append(
      event_type: "conversation_message",
      tick: tick,
      agent: agent,
      location: conversation.location,
      payload: {
        conversation_id: conversation.id,
        message: content
      }
    )

    msg
  end

  def self.join_conversation(conversation:, agent:, tick:)
    validate_active!(conversation)
    validate_same_location!(agent, conversation)
    validate_not_participant!(conversation, agent)
    validate_conversation_limit!(agent)

    conversation.conversation_participants.create!(agent: agent, joined_at_tick: tick)

    EventService.append(
      event_type: "conversation_message",
      tick: tick,
      agent: agent,
      location: conversation.location,
      payload: {
        conversation_id: conversation.id,
        message: "#{agent.name} joined the conversation",
        system: true
      }
    )

    conversation
  end

  def self.leave_conversation(conversation:, agent:, tick:)
    participant = conversation.conversation_participants.active.find_by(agent: agent)
    return unless participant

    participant.update!(left_at_tick: tick)

    EventService.append(
      event_type: "conversation_message",
      tick: tick,
      agent: agent,
      location: conversation.location,
      payload: {
        conversation_id: conversation.id,
        message: "#{agent.name} left the conversation",
        system: true
      }
    )

    end_conversation(conversation: conversation, tick: tick, reason: "all_left") if conversation.conversation_participants.active.none?
  end

  def self.end_conversation(conversation:, tick:, reason: "ended")
    return unless conversation.status == "active"

    conversation.update!(status: "ended", ended_at_tick: tick)

    EventService.append(
      event_type: "conversation_ended",
      tick: tick,
      location: conversation.location,
      payload: {
        conversation_id: conversation.id,
        reason: reason
      }
    )
  end

  def self.end_stale_conversations(tick:)
    Conversation.active.find_each do |conversation|
      if conversation.stale?(tick, threshold: STALE_THRESHOLD_TICKS)
        end_conversation(conversation: conversation, tick: tick, reason: "stale")
      end
    end
  end

  def self.active_count(agent)
    agent.conversation_participants.active
         .joins(:conversation)
         .where(conversations: { status: "active" })
         .count
  end

  def self.on_tick(tick)
    end_stale_conversations(tick: tick)
  end

  def self.name
    "ConversationService"
  end

  # --- Validations ---

  def self.validate_same_location!(agent, target)
    agent_location = agent.is_a?(Conversation) ? agent.location : agent.location
    target_location = target.is_a?(Conversation) ? target.location : target.location

    raise ConversationError, "Must be at the same location" unless agent_location == target_location
  end
  private_class_method :validate_same_location!

  def self.validate_conversation_limit!(agent)
    raise ConversationError, "Agent already in #{MAX_ACTIVE_CONVERSATIONS} active conversations" if active_count(agent) >= MAX_ACTIVE_CONVERSATIONS
  end
  private_class_method :validate_conversation_limit!

  def self.validate_active!(conversation)
    raise ConversationError, "Conversation is not active" unless conversation.status == "active"
  end
  private_class_method :validate_active!

  def self.validate_active_participant!(conversation, agent)
    unless conversation.conversation_participants.active.exists?(agent: agent)
      raise ConversationError, "Agent is not an active participant"
    end
  end
  private_class_method :validate_active_participant!

  def self.validate_not_participant!(conversation, agent)
    if conversation.conversation_participants.active.exists?(agent: agent)
      raise ConversationError, "Agent is already in this conversation"
    end
  end
  private_class_method :validate_not_participant!
end
