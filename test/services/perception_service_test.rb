require "test_helper"

class PerceptionServiceTest < ActiveSupport::TestCase
  test "build returns all expected top-level keys" do
    result = PerceptionService.build(agents(:alice))

    assert_kind_of Hash, result
    %i[tick location nearbyAgents activeConversations recentEvents recentMemories relevantMemories recentReflections unreflectedObservations relationships self availableActions allLocations].each do |key|
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

  test "availableActions returns base actions" do
    result = PerceptionService.build(agents(:alice))
    base = %w[move speak emote wait startConversation joinConversation leaveConversation conversationMessage]

    base.each do |action|
      assert_includes result[:availableActions], action
    end
  end

  test "availableActions includes reflect when enough unreflected observations" do
    alice = agents(:alice)
    alice.memories.observations.update_all(reflected_upon: true)

    5.times do |i|
      MemoryService.create_memory(
        agent: alice, content: "Observation #{i}", importance: 3, tick: 10 + i
      )
    end

    result = PerceptionService.build(alice)
    assert_includes result[:availableActions], "reflect"
  end

  test "availableActions excludes reflect when few unreflected observations" do
    alice = agents(:alice)
    alice.memories.observations.update_all(reflected_upon: true)

    result = PerceptionService.build(alice)
    assert_not_includes result[:availableActions], "reflect"
  end

  test "unreflectedObservations returns count and memories" do
    result = PerceptionService.build(agents(:alice))

    assert result[:unreflectedObservations].key?(:count)
    assert result[:unreflectedObservations].key?(:memories)
    assert_kind_of Integer, result[:unreflectedObservations][:count]
    assert_kind_of Array, result[:unreflectedObservations][:memories]
  end

  test "recentReflections returns array" do
    result = PerceptionService.build(agents(:alice))

    assert_kind_of Array, result[:recentReflections]
  end

  test "allLocations includes all locations with agent counts" do
    result = PerceptionService.build(agents(:alice))

    assert_equal Location.count, result[:allLocations].length

    town_square = result[:allLocations].find { |l| l[:name] == "Town Square" }
    assert_not_nil town_square
    assert town_square.key?(:agentCount)
    assert town_square.key?(:description)
  end

  test "relationships includes non-stranger relationships" do
    # alice_knows_bob fixture has familiarity 40 (above 10 threshold)
    result = PerceptionService.build(agents(:alice))

    assert_kind_of Array, result[:relationships]
    assert result[:relationships].any? { |r| r[:targetAgentId] == agents(:bob).id }
  end

  test "relationships excludes strangers" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Create a low-familiarity relationship
    Relationship.where(agent: alice, target_agent: charlie).delete_all
    Relationship.create!(agent: alice, target_agent: charlie, familiarity: 5)

    result = PerceptionService.build(alice)

    assert_not result[:relationships].any? { |r| r[:targetAgentId] == charlie.id }
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
