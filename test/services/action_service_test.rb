require "test_helper"

class ActionServiceTest < ActiveSupport::TestCase
  # --- Validation ---

  test "raises on unknown action type" do
    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: agents(:alice), action_type: "dance")
    end
    assert_equal "Unknown action type: dance", error.message
  end

  test "raises when agent is not active" do
    alice = agents(:alice)
    alice.update!(status: "offline")

    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: alice, action_type: "wait")
    end
    assert_equal "Agent is not active", error.message
  end

  test "raises when stamina is insufficient for move" do
    alice = agents(:alice)
    alice.update!(stamina: 3)

    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: alice,
        action_type: "move",
        params: { target_location_id: locations(:market).id }
      )
    end
    assert_equal "Insufficient stamina", error.message
  end

  test "raises when move missing targetLocationId" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: agents(:alice), action_type: "move", params: {})
    end
  end

  test "raises when speak missing message" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: agents(:alice), action_type: "speak", params: {})
    end
  end

  test "raises when emote missing description" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: agents(:alice), action_type: "emote", params: {})
    end
  end

  # --- Wait ---

  test "wait succeeds with no event and no stamina cost" do
    alice = agents(:alice)
    original_stamina = alice.stamina

    result = ActionService.execute(agent: alice, action_type: "wait")

    assert result[:success]
    assert_nil result[:event]
    assert_equal original_stamina, alice.reload.stamina
  end

  test "wait does not emit any events" do
    assert_no_difference "Event.count" do
      ActionService.execute(agent: agents(:alice), action_type: "wait")
    end
  end

  # --- Move ---

  test "move changes agent location and deducts stamina" do
    alice = agents(:alice)
    market = locations(:market)

    result = ActionService.execute(
      agent: alice,
      action_type: "move",
      params: { target_location_id: market.id }
    )

    assert result[:success]
    assert_equal 95, alice.reload.stamina
    assert_equal market, alice.location
  end

  test "move emits agent_moved and stamina_changed events" do
    # Alice is in active_conversation fixture, so move also emits leave + end events
    ActionService.execute(
      agent: agents(:alice),
      action_type: "move",
      params: { target_location_id: locations(:market).id }
    )

    event_types = Event.pluck(:event_type)
    assert_includes event_types, "agent_moved"
    assert_includes event_types, "stamina_changed"
  end

  test "move raises for nonexistent location" do
    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "move",
        params: { target_location_id: "loc_nonexistent000000000000000" }
      )
    end
    assert_equal "Location not found", error.message
  end

  test "move rolls back stamina on movement error" do
    alice = agents(:alice)
    original_stamina = alice.stamina

    assert_raises(WorldService::MovementError) do
      ActionService.execute(
        agent: alice,
        action_type: "move",
        params: { target_location_id: locations(:town_square).id }
      )
    end

    assert_equal original_stamina, alice.reload.stamina
  end

  # --- Speak ---

  test "speak emits agent_spoke event and deducts stamina" do
    alice = agents(:alice)

    result = ActionService.execute(
      agent: alice,
      action_type: "speak",
      params: { message: "Hello world!" }
    )

    assert result[:success]
    assert_equal 99, alice.reload.stamina

    event = Event.where(event_type: "agent_spoke", agent: alice).last
    assert_equal "Hello world!", event.payload["message"]
  end

  test "speak event is at agent current location" do
    alice = agents(:alice)

    ActionService.execute(
      agent: alice,
      action_type: "speak",
      params: { message: "Hello!" }
    )

    event = Event.where(event_type: "agent_spoke", agent: alice).last
    assert_equal alice.location_id, event.location_id
  end

  # --- Emote ---

  test "emote emits agent_action event with type emote" do
    alice = agents(:alice)

    result = ActionService.execute(
      agent: alice,
      action_type: "emote",
      params: { description: "waves enthusiastically" }
    )

    assert result[:success]
    assert_equal 99, alice.reload.stamina

    event = Event.where(event_type: "agent_action", agent: alice).last
    assert_equal "emote", event.payload["type"]
    assert_equal "waves enthusiastically", event.payload["description"]
  end

  # --- Response format ---

  test "execute returns tick in response" do
    result = ActionService.execute(agent: agents(:alice), action_type: "wait")

    assert result.key?(:tick)
    assert_equal SimulationService.current_tick, result[:tick]
  end

  test "move with exact stamina succeeds" do
    alice = agents(:alice)
    alice.update!(stamina: 5)

    result = ActionService.execute(
      agent: alice,
      action_type: "move",
      params: { target_location_id: locations(:market).id }
    )

    assert result[:success]
    assert_equal 0, alice.reload.stamina
  end

  # --- Start Conversation ---

  test "startConversation creates conversation and deducts 2 stamina" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    result = ActionService.execute(
      agent: alice,
      action_type: "startConversation",
      params: { target_agent_id: charlie.id, message: "Hey!" }
    )

    assert result[:success]
    assert_equal 98, alice.reload.stamina
    assert_equal 1, Conversation.where(location: alice.location).active.count - 1  # minus existing fixture
  end

  test "startConversation raises for missing target_agent_id" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "startConversation",
        params: { message: "Hello" }
      )
    end
  end

  test "startConversation raises for missing message" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "startConversation",
        params: { target_agent_id: agents(:charlie).id }
      )
    end
  end

  test "startConversation raises for nonexistent target agent" do
    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "startConversation",
        params: { target_agent_id: "agt_nonexistent000000000000000", message: "Hi!" }
      )
    end
    assert_equal "Target agent not found", error.message
  end

  # --- Conversation Message ---

  test "conversationMessage creates message and deducts 1 stamina" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    result = ActionService.execute(
      agent: alice,
      action_type: "conversationMessage",
      params: { conversation_id: conversation.id, message: "How are you?" }
    )

    assert result[:success]
    assert_equal 99, alice.reload.stamina
  end

  test "conversationMessage raises for missing conversation_id" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "conversationMessage",
        params: { message: "Hello" }
      )
    end
  end

  # --- Join Conversation ---

  test "joinConversation adds agent and deducts 1 stamina" do
    charlie = agents(:charlie)
    conversation = conversations(:active_conversation)

    result = ActionService.execute(
      agent: charlie,
      action_type: "joinConversation",
      params: { conversation_id: conversation.id }
    )

    assert result[:success]
    assert_equal 99, charlie.reload.stamina
    assert conversation.conversation_participants.exists?(agent: charlie)
  end

  # --- Leave Conversation ---

  test "leaveConversation removes agent with 0 stamina cost" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)
    original_stamina = alice.stamina

    result = ActionService.execute(
      agent: alice,
      action_type: "leaveConversation",
      params: { conversation_id: conversation.id }
    )

    assert result[:success]
    assert_equal original_stamina, alice.reload.stamina

    participant = conversation.conversation_participants.find_by(agent: alice)
    assert_not_nil participant.left_at_tick
  end

  # --- Move auto-leaves conversations ---

  test "move auto-leaves active conversations" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)

    ActionService.execute(
      agent: alice,
      action_type: "move",
      params: { target_location_id: locations(:market).id }
    )

    participant = conversation.conversation_participants.find_by(agent: alice)
    assert_not_nil participant.left_at_tick
  end

  test "move auto-ends conversation when last participant leaves" do
    alice = agents(:alice)
    conversation = conversations(:active_conversation)
    # Alice is the only participant in the fixture

    ActionService.execute(
      agent: alice,
      action_type: "move",
      params: { target_location_id: locations(:market).id }
    )

    assert_equal "ended", conversation.reload.status
  end

  # --- Rest ---

  test "rest restores energy and deducts 2 stamina" do
    alice = agents(:alice)
    alice.update_column(:energy, 50)

    result = ActionService.execute(agent: alice, action_type: "rest")

    assert result[:success]
    assert_equal 98, alice.reload.stamina
    assert_equal 80, alice.energy
  end

  # --- Eat ---

  test "eat consumes food, restores energy, deducts 1 stamina" do
    alice = agents(:alice)
    alice.update_columns(food: 50, energy: 30)

    result = ActionService.execute(agent: alice, action_type: "eat")

    assert result[:success]
    assert_equal 99, alice.reload.stamina
    assert_equal 30, alice.food
    assert_equal 70, alice.energy
  end

  test "eat raises when insufficient food" do
    alice = agents(:alice)
    alice.update_column(:food, 5)

    assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: alice, action_type: "eat")
    end
  end

  # --- Trade ---

  test "trade transfers resource and deducts 1 stamina" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    result = ActionService.execute(
      agent: alice,
      action_type: "trade",
      params: { target_agent_id: charlie.id, resource: "currency", amount: "25" }
    )

    assert result[:success]
    assert_equal 99, alice.reload.stamina
    assert_equal 75, alice.currency
    assert_equal 125, charlie.reload.currency
  end

  test "trade raises for missing params" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: agents(:alice), action_type: "trade", params: {})
    end
  end

  # --- Exhaustion ---

  test "exhausted agent cannot speak" do
    alice = agents(:alice)
    alice.update_column(:energy, 0)

    error = assert_raises(ActionService::ActionError) do
      ActionService.execute(agent: alice, action_type: "speak", params: { message: "Hi" })
    end
    assert_match(/exhausted/, error.message)
  end

  test "exhausted agent can still wait" do
    alice = agents(:alice)
    alice.update_column(:energy, 0)

    result = ActionService.execute(agent: alice, action_type: "wait")
    assert result[:success]
  end

  test "exhausted agent can still rest" do
    alice = agents(:alice)
    alice.update_columns(energy: 0, stamina: 10)

    result = ActionService.execute(agent: alice, action_type: "rest")
    assert result[:success]
    assert_equal 30, alice.reload.energy
  end

  test "exhausted agent can still eat" do
    alice = agents(:alice)
    alice.update_columns(energy: 0, food: 50, stamina: 10)

    result = ActionService.execute(agent: alice, action_type: "eat")
    assert result[:success]
    assert_equal 40, alice.reload.energy
  end
end
