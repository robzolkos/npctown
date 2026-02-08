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
    assert_difference "Event.count", 2 do
      ActionService.execute(
        agent: agents(:alice),
        action_type: "move",
        params: { target_location_id: locations(:market).id }
      )
    end

    event_types = Event.last(2).map(&:event_type)
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
end
