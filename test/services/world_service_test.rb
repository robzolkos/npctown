require "test_helper"

class WorldServiceTest < ActiveSupport::TestCase
  # --- move_agent ---

  test "move_agent updates agent location" do
    alice = agents(:alice)
    market = locations(:market)

    WorldService.move_agent(agent: alice, location: market, tick: 1)

    alice.reload
    assert_equal market, alice.location
  end

  test "move_agent emits agent_moved event" do
    alice = agents(:alice)
    market = locations(:market)

    assert_difference "Event.count", 1 do
      WorldService.move_agent(agent: alice, location: market, tick: 1)
    end

    event = Event.last
    assert_equal "agent_moved", event.event_type
    assert_equal 1, event.tick
    assert_equal alice.id, event.agent_id
    assert_equal market.id, event.location_id
  end

  test "move_agent event payload contains from and to locations" do
    alice = agents(:alice)
    town_square = locations(:town_square)
    market = locations(:market)

    event = WorldService.move_agent(agent: alice, location: market, tick: 1)

    assert_equal town_square.id, event.payload["from_location_id"]
    assert_equal "Town Square", event.payload["from_location_name"]
    assert_equal market.id, event.payload["to_location_id"]
    assert_equal "Market", event.payload["to_location_name"]
  end

  test "move_agent raises when agent is already at target location" do
    alice = agents(:alice)
    town_square = locations(:town_square)

    assert_raises(WorldService::MovementError) do
      WorldService.move_agent(agent: alice, location: town_square, tick: 1)
    end
  end

  test "move_agent works when agent has no current location" do
    alice = agents(:alice)
    alice.update_column(:location_id, nil)
    market = locations(:market)

    event = WorldService.move_agent(agent: alice, location: market, tick: 1)

    alice.reload
    assert_equal market, alice.location
    assert_nil event.payload["from_location_id"]
    assert_nil event.payload["from_location_name"]
  end

  # --- agents_at ---

  test "agents_at returns agents at a location" do
    agents_at_square = WorldService.agents_at(locations(:town_square))
    assert_includes agents_at_square, agents(:alice)
    assert_not_includes agents_at_square, agents(:bob)
  end

  # --- location_for ---

  test "location_for returns agent current location" do
    assert_equal locations(:town_square), WorldService.location_for(agents(:alice))
    assert_equal locations(:market), WorldService.location_for(agents(:bob))
  end

  # --- setup_world ---

  test "setup_world returns MVP locations" do
    locations = WorldService.setup_world

    assert_equal 3, locations.length
    assert_equal [ "Town Square", "Market", "Library" ], locations.map(&:name)
    assert locations.all? { |l| l.description.present? }
  end

  test "setup_world is idempotent" do
    assert_no_difference "Location.count" do
      WorldService.setup_world
    end
  end
end
