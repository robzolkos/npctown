require "test_helper"

class SpectatorEventFormatterTest < ActiveSupport::TestCase
  test "spectator_visible? returns true for visible event types" do
    SpectatorEventFormatter::SPECTATOR_TYPES.each do |type|
      event = Event.new(event_type: type, tick: 1, payload: {})
      assert SpectatorEventFormatter.spectator_visible?(event), "Expected #{type} to be visible"
    end
  end

  test "spectator_visible? returns false for hidden event types" do
    SpectatorEventFormatter::HIDDEN_TYPES.each do |type|
      event = Event.new(event_type: type, tick: 1, payload: {})
      assert_not SpectatorEventFormatter.spectator_visible?(event), "Expected #{type} to be hidden"
    end
  end

  test "format returns correct structure" do
    event = events(:alice_registered)
    result = SpectatorEventFormatter.format(event)

    assert_equal event.id, result[:id]
    assert_equal event.tick, result[:tick]
    assert_equal "agent_registered", result[:type]
    assert result[:timestamp].present?
    assert result[:message].is_a?(String)
    assert result[:details].is_a?(Hash)
  end

  test "format_many skips hidden events" do
    tick_event = Event.new(event_type: "tick_advanced", tick: 1, payload: { tick: 1 })
    tick_event.save!(validate: false) # bypass KSUID for test
    all_events = [ events(:alice_registered), tick_event ]

    results = SpectatorEventFormatter.format_many(all_events)
    types = results.map { |r| r[:type] }

    assert_includes types, "agent_registered"
    assert_not_includes types, "tick_advanced"
  ensure
    tick_event&.destroy
  end

  test "human_message for agent_registered" do
    event = Event.new(
      event_type: "agent_registered",
      tick: 0,
      payload: { "agent_name" => "Alice" }
    )
    assert_equal "Alice joined the town", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for agent_moved" do
    event = Event.new(
      event_type: "agent_moved",
      tick: 1,
      payload: { "to_location_name" => "Market" },
      agent: agents(:alice)
    )
    assert_equal "Alice moved to Market", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for agent_spoke" do
    event = Event.new(
      event_type: "agent_spoke",
      tick: 1,
      payload: { "message" => "Hello everyone!" },
      agent: agents(:alice)
    )
    assert_equal "Alice: \"Hello everyone!\"", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for agent_action emote" do
    event = Event.new(
      event_type: "agent_action",
      tick: 1,
      payload: { "type" => "emote", "description" => "waves happily" },
      agent: agents(:alice)
    )
    assert_equal "Alice waves happily", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for conversation_started" do
    event = Event.new(
      event_type: "conversation_started",
      tick: 1,
      payload: { "target_agent_id" => agents(:bob).id },
      agent: agents(:alice)
    )
    msg = SpectatorEventFormatter.human_message(event)
    assert_equal "Alice started a conversation with Bob", msg
  end

  test "human_message for conversation_message" do
    event = Event.new(
      event_type: "conversation_message",
      tick: 1,
      payload: { "message" => "Hi there" },
      agent: agents(:alice)
    )
    assert_equal "Alice (in conversation): \"Hi there\"", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for conversation_ended" do
    event = Event.new(
      event_type: "conversation_ended",
      tick: 5,
      payload: { "reason" => "stale" }
    )
    assert_equal "A conversation ended (stale)", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for plan_created" do
    event = Event.new(
      event_type: "plan_created",
      tick: 1,
      payload: { "goal" => "explore the market" },
      agent: agents(:alice)
    )
    assert_equal "Alice made a plan: explore the market", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for plan_completed" do
    event = Event.new(
      event_type: "plan_completed",
      tick: 10,
      payload: { "goal" => "explore the market" },
      agent: agents(:alice)
    )
    assert_equal "Alice completed their plan: explore the market", SpectatorEventFormatter.human_message(event)
  end

  test "human_message for resource_changed trade" do
    event = Event.new(
      event_type: "resource_changed",
      tick: 1,
      payload: { "reason" => "trade", "resource" => "food", "amount" => 10, "target_agent_id" => agents(:bob).id },
      agent: agents(:alice)
    )
    msg = SpectatorEventFormatter.human_message(event)
    assert_equal "Alice traded 10 food with Bob", msg
  end

  test "human_message handles missing payload gracefully" do
    event = Event.new(
      event_type: "agent_moved",
      tick: 1,
      payload: nil,
      agent: agents(:alice)
    )
    msg = SpectatorEventFormatter.human_message(event)
    assert_equal "Alice moved to somewhere", msg
  end

  test "human_message handles missing agent gracefully" do
    event = Event.new(
      event_type: "agent_moved",
      tick: 1,
      payload: { "to_location_name" => "Market" }
    )
    msg = SpectatorEventFormatter.human_message(event)
    assert_equal "Someone moved to Market", msg
  end
end
