require "test_helper"

class EventServiceTest < ActiveSupport::TestCase
  test "append creates a new event" do
    assert_difference "Event.count", 1 do
      EventService.append(
        event_type: "agent_registered",
        tick: 0,
        payload: { agent_name: "NewAgent" },
        agent: agents(:alice),
        location: locations(:town_square)
      )
    end
  end

  test "append raises for invalid event type" do
    assert_raises(EventService::InvalidEventType) do
      EventService.append(event_type: "fake_event", tick: 0)
    end
  end

  test "append without agent or location" do
    event = EventService.append(event_type: "tick_advanced", tick: 5, payload: { tick: 5 })
    assert event.persisted?
    assert_nil event.agent_id
    assert_nil event.location_id
  end

  test "append returns event with correct prefixed ID" do
    event = EventService.append(event_type: "tick_advanced", tick: 10)
    assert event.id.start_with?("evt_")
  end

  test "query filters by event_type" do
    EventService.append(event_type: "agent_moved", tick: 1, agent: agents(:alice), location: locations(:market))
    results = EventService.query(event_type: "agent_moved")
    assert results.all? { |e| e.event_type == "agent_moved" }
  end

  test "query filters by since_tick" do
    EventService.append(event_type: "tick_advanced", tick: 10)
    EventService.append(event_type: "tick_advanced", tick: 20)
    results = EventService.query(since_tick: 15)
    assert results.all? { |e| e.tick >= 15 }
  end

  test "query filters by location" do
    EventService.append(event_type: "agent_spoke", tick: 1, agent: agents(:alice), location: locations(:town_square))
    results = EventService.query(location: locations(:town_square))
    assert results.all? { |e| e.location_id == locations(:town_square).id }
  end

  test "since returns events from tick onward" do
    EventService.append(event_type: "tick_advanced", tick: 50)
    results = EventService.since(50)
    assert results.any?
    assert results.all? { |e| e.tick >= 50 }
  end

  test "at_location filters correctly" do
    EventService.append(event_type: "agent_spoke", tick: 1, location: locations(:market))
    results = EventService.at_location(locations(:market))
    assert results.all? { |e| e.location_id == locations(:market).id }
  end
end
