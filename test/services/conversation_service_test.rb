require "test_helper"

class ConversationServiceTest < ActiveSupport::TestCase
  # --- Start Conversation ---

  test "start_conversation creates conversation with participants and message" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    conversation = ConversationService.start_conversation(
      initiator: alice,
      target_agent: charlie,
      message: "Hey Charlie!",
      tick: 10
    )

    assert_equal "active", conversation.status
    assert_equal alice.location, conversation.location
    assert_equal 10, conversation.started_at_tick
    assert_equal 2, conversation.conversation_participants.count
    assert_equal 1, conversation.conversation_messages.count
    assert_equal "Hey Charlie!", conversation.conversation_messages.first.content
  end

  test "start_conversation emits conversation_started event" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    ConversationService.start_conversation(initiator: alice, target_agent: charlie, message: "Hi!", tick: 10)

    event = Event.where(event_type: "conversation_started").last
    assert_equal alice.id, event.agent_id
    assert_equal alice.location_id, event.location_id
    assert_equal "Hi!", event.payload["message"]
    assert_equal charlie.id, event.payload["target_agent_id"]
  end

  test "start_conversation fails if target at different location" do
    alice = agents(:alice)     # Town Square
    bob = agents(:bob)         # Market

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.start_conversation(initiator: alice, target_agent: bob, message: "Hi!", tick: 10)
    end
    assert_equal "Must be at the same location", error.message
  end

  test "start_conversation fails if initiator at max conversations" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Create 2 active conversations for alice
    2.times do |i|
      conv = Conversation.create!(location: alice.location, status: "active", started_at_tick: i)
      conv.conversation_participants.create!(agent: alice, joined_at_tick: i)
    end

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.start_conversation(initiator: alice, target_agent: charlie, message: "Hi!", tick: 10)
    end
    assert_match(/already in 2 active conversations/, error.message)
  end

  test "start_conversation fails if target at max conversations" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Create 2 active conversations for charlie
    2.times do |i|
      conv = Conversation.create!(location: charlie.location, status: "active", started_at_tick: i)
      conv.conversation_participants.create!(agent: charlie, joined_at_tick: i)
    end

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.start_conversation(initiator: alice, target_agent: charlie, message: "Hi!", tick: 10)
    end
    assert_match(/already in 2 active conversations/, error.message)
  end

  # --- Add Message ---

  test "add_message creates message and emits event" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    msg = ConversationService.add_message(conversation: conversation, agent: alice, content: "Hello!", tick: 10)

    assert_equal "Hello!", msg.content
    assert_equal 10, msg.tick

    event = Event.where(event_type: "conversation_message", agent: alice).last
    assert_equal "Hello!", event.payload["message"]
    assert_equal conversation.id, event.payload["conversation_id"]
  end

  test "add_message fails if agent not an active participant" do
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.add_message(conversation: conversation, agent: charlie, content: "Hello!", tick: 10)
    end
    assert_equal "Agent is not an active participant", error.message
  end

  test "add_message fails if conversation is ended" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)
    conversation.update!(status: "ended", ended_at_tick: 8)

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.add_message(conversation: conversation, agent: alice, content: "Hello!", tick: 10)
    end
    assert_equal "Conversation is not active", error.message
  end

  # --- Join Conversation ---

  test "join_conversation adds participant" do
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    ConversationService.join_conversation(conversation: conversation, agent: charlie, tick: 10)

    assert conversation.conversation_participants.exists?(agent: charlie)
    assert_equal 10, conversation.conversation_participants.find_by(agent: charlie).joined_at_tick
  end

  test "join_conversation emits system message event" do
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    ConversationService.join_conversation(conversation: conversation, agent: charlie, tick: 10)

    event = Event.where(event_type: "conversation_message", agent: charlie).last
    assert event.payload["system"]
    assert_match(/joined the conversation/, event.payload["message"])
  end

  test "join_conversation fails if at different location" do
    bob = agents(:bob)  # Market
    conversation = conversations(:active_conversation)  # Town Square

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.join_conversation(conversation: conversation, agent: bob, tick: 10)
    end
    assert_equal "Must be at the same location", error.message
  end

  test "join_conversation fails if already a participant" do
    alice = agents(:alice)  # Already in active_conversation
    conversation = conversations(:active_conversation)

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.join_conversation(conversation: conversation, agent: alice, tick: 10)
    end
    assert_equal "Agent is already in this conversation", error.message
  end

  test "join_conversation fails if at max conversations" do
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    2.times do |i|
      conv = Conversation.create!(location: charlie.location, status: "active", started_at_tick: i)
      conv.conversation_participants.create!(agent: charlie, joined_at_tick: i)
    end

    error = assert_raises(ConversationService::ConversationError) do
      ConversationService.join_conversation(conversation: conversation, agent: charlie, tick: 10)
    end
    assert_match(/already in 2 active conversations/, error.message)
  end

  # --- Leave Conversation ---

  test "leave_conversation sets left_at_tick" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    ConversationService.leave_conversation(conversation: conversation, agent: alice, tick: 10)

    participant = conversation.conversation_participants.find_by(agent: alice)
    assert_equal 10, participant.left_at_tick
  end

  test "leave_conversation emits system message" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    ConversationService.leave_conversation(conversation: conversation, agent: alice, tick: 10)

    event = Event.where(event_type: "conversation_message", agent: alice).last
    assert event.payload["system"]
    assert_match(/left the conversation/, event.payload["message"])
  end

  test "leave_conversation auto-ends when last participant leaves" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    ConversationService.leave_conversation(conversation: conversation, agent: alice, tick: 10)

    assert_equal "ended", conversation.reload.status
    assert_equal 10, conversation.ended_at_tick

    event = Event.where(event_type: "conversation_ended").last
    assert_equal "all_left", event.payload["reason"]
  end

  test "leave_conversation does not end when other participants remain" do
    alice = agents(:alice)
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    # Add charlie as a participant
    conversation.conversation_participants.create!(agent: charlie, joined_at_tick: 5)

    ConversationService.leave_conversation(conversation: conversation, agent: alice, tick: 10)

    assert_equal "active", conversation.reload.status
  end

  # --- End Stale Conversations ---

  test "end_stale_conversations ends conversations with no messages for 5+ ticks" do
    conversation = conversations(:active_conversation)
    # active_conversation has messages at tick 5, so it's stale at tick 10+

    ConversationService.end_stale_conversations(tick: 10)

    assert_equal "ended", conversation.reload.status
    assert_equal 10, conversation.ended_at_tick

    event = Event.where(event_type: "conversation_ended").last
    assert_equal "stale", event.payload["reason"]
  end

  test "end_stale_conversations does not end recent conversations" do
    conversation = conversations(:active_conversation)
    # Add a recent message
    conversation.conversation_messages.create!(agent: agents(:alice), content: "recent", tick: 8)

    ConversationService.end_stale_conversations(tick: 10)

    assert_equal "active", conversation.reload.status
  end

  # --- Active Count ---

  test "active_count returns correct count" do
    alice = agents(:alice)

    # alice is already in active_conversation (fixture)
    assert_equal 1, ConversationService.active_count(alice)

    # Add another
    conv = Conversation.create!(location: alice.location, status: "active", started_at_tick: 10)
    conv.conversation_participants.create!(agent: alice, joined_at_tick: 10)

    assert_equal 2, ConversationService.active_count(alice)
  end

  test "active_count excludes left conversations" do
    alice = agents(:alice)
    # alice is in active_conversation, leave it
    conversation_participants(:alice_in_conversation).update!(left_at_tick: 10)

    assert_equal 0, ConversationService.active_count(alice)
  end

  test "active_count excludes ended conversations" do
    alice = agents(:alice)
    conversations(:active_conversation).update!(status: "ended", ended_at_tick: 10)

    assert_equal 0, ConversationService.active_count(alice)
  end

  # --- on_tick ---

  test "on_tick calls end_stale_conversations" do
    conversation = conversations(:active_conversation)

    ConversationService.on_tick(10)

    assert_equal "ended", conversation.reload.status
  end
end
