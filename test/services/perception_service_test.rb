require "test_helper"

class PerceptionServiceTest < ActiveSupport::TestCase
  test "build returns all expected top-level keys" do
    result = PerceptionService.build(agents(:alice))

    assert_kind_of Hash, result
    %i[tick location nearbyAgents activeConversations recentEvents recentMemories relevantMemories self availableActions allLocations].each do |key|
      assert result.key?(key), "Missing key: #{key}"
    end
  end

  test "tick returns current simulation tick" do
    result = PerceptionService.build(agents(:alice))

    assert_equal SimulationService.current_tick, result[:tick]
  end

  test "location returns agent's current location" do
    result = PerceptionService.build(agents(:alice))

    assert_equal agents(:alice).location.id, result[:location][:id]
    assert_equal "Town Square", result[:location][:name]
    assert result[:location][:description].present?
  end

  test "nearbyAgents excludes self" do
    result = PerceptionService.build(agents(:alice))
    ids = result[:nearbyAgents].map { |a| a[:id] }

    assert_not_includes ids, agents(:alice).id
  end

  test "nearbyAgents includes agents at same location" do
    # Move bob to Town Square so he's nearby alice
    agents(:bob).update!(location: locations(:town_square))

    result = PerceptionService.build(agents(:alice))
    ids = result[:nearbyAgents].map { |a| a[:id] }

    assert_includes ids, agents(:bob).id
  end

  test "nearbyAgents does not include agents at other locations" do
    # Bob is at Market (different from Alice at Town Square)
    result = PerceptionService.build(agents(:alice))
    ids = result[:nearbyAgents].map { |a| a[:id] }

    assert_not_includes ids, agents(:bob).id
  end

  test "nearbyAgents contains expected fields" do
    agents(:bob).update!(location: locations(:town_square))

    result = PerceptionService.build(agents(:alice))
    nearby = result[:nearbyAgents].find { |a| a[:id] == agents(:bob).id }

    assert_not_nil nearby
    assert_equal "Bob", nearby[:name]
    assert nearby.key?(:description)
    assert nearby.key?(:personalityTraits)
    assert nearby.key?(:status)
  end

  test "recentEvents scoped to agent's location" do
    # Create an event at Market (not Alice's location)
    EventService.append(
      event_type: "agent_spoke",
      tick: 1,
      agent: agents(:bob),
      location: locations(:market),
      payload: { message: "hello" }
    )

    result = PerceptionService.build(agents(:alice))
    event_locations = result[:recentEvents].map { |e| e[:payload] }

    # Should not contain the Market event
    result[:recentEvents].each do |event|
      assert_not_equal "hello", event[:payload]["message"]
    end
  end

  test "self contains agent's resource values" do
    result = PerceptionService.build(agents(:alice))
    self_data = result[:self]

    assert_equal agents(:alice).id, self_data[:id]
    assert_equal agents(:alice).name, self_data[:name]
    assert_equal agents(:alice).stamina, self_data[:stamina]
    assert_equal agents(:alice).food, self_data[:food]
    assert_equal agents(:alice).energy, self_data[:energy]
    assert_equal agents(:alice).currency, self_data[:currency]
    assert_equal agents(:alice).status, self_data[:status]
  end

  test "availableActions returns expected list" do
    result = PerceptionService.build(agents(:alice))

    assert_equal %w[move speak emote wait startConversation joinConversation leaveConversation conversationMessage], result[:availableActions]
  end

  test "allLocations includes all locations with agent counts" do
    result = PerceptionService.build(agents(:alice))

    assert_equal Location.count, result[:allLocations].length

    town_square = result[:allLocations].find { |l| l[:name] == "Town Square" }
    assert_not_nil town_square
    assert town_square.key?(:agentCount)
    assert town_square.key?(:description)
  end

  test "activeConversations includes conversations at agent's location" do
    result = PerceptionService.build(agents(:alice))

    assert result[:activeConversations].any? { |c| c[:id] == conversations(:active_conversation).id }
  end

  test "activeConversations includes participant names and messages" do
    result = PerceptionService.build(agents(:alice))
    conv = result[:activeConversations].find { |c| c[:id] == conversations(:active_conversation).id }

    assert_not_nil conv
    assert conv[:participants].any? { |p| p[:name] == "Alice" }
    assert conv[:recentMessages].any? { |m| m[:content] == "Hello everyone!" }
  end
end
