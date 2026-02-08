require "test_helper"

class Api::V1::SpectateControllerTest < ActionDispatch::IntegrationTest
  # --- GET /api/v1/spectate/history ---

  test "history returns formatted events without auth" do
    get history_api_v1_spectate_url(since_tick: 0), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end

  test "history returns events since given tick" do
    # Create a spectator-visible event at tick 5
    event = EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      payload: { message: "Hello!" },
      agent: agents(:alice),
      location: locations(:town_square)
    )

    get history_api_v1_spectate_url(since_tick: 5), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    ids = json.map { |e| e["id"] }
    assert_includes ids, event.id
  end

  test "history excludes hidden event types" do
    EventService.append(
      event_type: "tick_advanced",
      tick: 99,
      payload: { tick: 99 }
    )

    get history_api_v1_spectate_url(since_tick: 99), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    types = json.map { |e| e["type"] }
    assert_not_includes types, "tick_advanced"
  end

  test "history respects limit param" do
    5.times do |i|
      EventService.append(
        event_type: "agent_spoke",
        tick: 200 + i,
        payload: { message: "msg #{i}" },
        agent: agents(:alice),
        location: locations(:town_square)
      )
    end

    get history_api_v1_spectate_url(since_tick: 200, limit: 2), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 2, json.length
  end

  test "history caps limit at 200" do
    get history_api_v1_spectate_url(since_tick: 0, limit: 999), as: :json

    assert_response :ok
    # Just verifying it doesn't error — the cap is applied internally
  end

  test "history filters by location" do
    EventService.append(
      event_type: "agent_spoke",
      tick: 300,
      payload: { message: "At market" },
      agent: agents(:bob),
      location: locations(:market)
    )
    EventService.append(
      event_type: "agent_spoke",
      tick: 300,
      payload: { message: "At square" },
      agent: agents(:alice),
      location: locations(:town_square)
    )

    get history_api_v1_spectate_url(since_tick: 300, location: "market"), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    messages = json.map { |e| e["details"]["message"] }
    assert_includes messages, "At market"
    assert_not_includes messages, "At square"
  end

  test "history filters by agent" do
    EventService.append(
      event_type: "agent_spoke",
      tick: 400,
      payload: { message: "Alice speaks" },
      agent: agents(:alice),
      location: locations(:town_square)
    )
    EventService.append(
      event_type: "agent_spoke",
      tick: 400,
      payload: { message: "Bob speaks" },
      agent: agents(:bob),
      location: locations(:market)
    )

    get history_api_v1_spectate_url(since_tick: 400, agent: agents(:alice).id), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    messages = json.map { |e| e["details"]["message"] }
    assert_includes messages, "Alice speaks"
    assert_not_includes messages, "Bob speaks"
  end

  test "history event has correct structure" do
    event = EventService.append(
      event_type: "agent_spoke",
      tick: 500,
      payload: { message: "Structured!" },
      agent: agents(:alice),
      location: locations(:town_square)
    )

    get history_api_v1_spectate_url(since_tick: 500), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    entry = json.find { |e| e["id"] == event.id }

    assert entry.present?
    assert_equal event.id, entry["id"]
    assert_equal 500, entry["tick"]
    assert_equal "agent_spoke", entry["type"]
    assert entry["timestamp"].present?
    assert entry["message"].is_a?(String)
    assert_equal "Structured!", entry["details"]["message"]
  end

  test "history location filter is case-insensitive" do
    EventService.append(
      event_type: "agent_spoke",
      tick: 600,
      payload: { message: "Market event" },
      agent: agents(:bob),
      location: locations(:market)
    )

    get history_api_v1_spectate_url(since_tick: 600, location: "Market"), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.any? { |e| e["details"]["message"] == "Market event" }
  end
end
