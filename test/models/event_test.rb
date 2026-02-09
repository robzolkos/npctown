require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "valid event" do
    event = Event.new(
      event_type: "agent_registered",
      tick: 0,
      payload: { agent_name: "Test" },
      agent: agents(:alice),
      location: locations(:town_square)
    )
    assert event.valid?
  end

  test "requires valid event_type" do
    event = Event.new(event_type: "invalid", tick: 0)
    assert_not event.valid?
  end

  test "requires non-negative tick" do
    event = Event.new(event_type: "tick_advanced", tick: -1)
    assert_not event.valid?
  end

  test "agent and location are optional" do
    event = Event.new(event_type: "tick_advanced", tick: 1, payload: {})
    assert event.valid?
  end

  test "of_type scope" do
    events = Event.of_type("agent_registered")
    assert events.all? { |e| e.event_type == "agent_registered" }
  end

  test "since_tick scope" do
    events = Event.since_tick(1)
    assert events.all? { |e| e.tick >= 1 }
  end

  test "TYPES constant includes all event types" do
    assert_includes Event::TYPES, "agent_registered"
    assert_includes Event::TYPES, "tick_advanced"
    assert_includes Event::TYPES, "conversation_started"
    assert_includes Event::TYPES, "plan_created"
    assert_includes Event::TYPES, "plan_updated"
    assert_includes Event::TYPES, "plan_completed"
    assert_includes Event::TYPES, "plan_abandoned"
    assert_includes Event::TYPES, "gate_application_started"
    assert_includes Event::TYPES, "gate_interview_question"
    assert_includes Event::TYPES, "gate_interview_answer"
    assert_includes Event::TYPES, "gate_application_passed"
    assert_includes Event::TYPES, "gate_application_failed"
    assert_equal 22, Event::TYPES.length
  end
end
