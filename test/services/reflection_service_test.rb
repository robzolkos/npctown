require "test_helper"

class ReflectionServiceTest < ActiveSupport::TestCase
  setup do
    @alice = agents(:alice)
    @bob = agents(:bob)
    @market = locations(:market)
    @town_square = locations(:town_square)
  end

  # --- on_tick ---

  test "on_tick enqueues job at interval boundary" do
    ProcessReflectionsJob.expects(:perform_async).with(100)
    ReflectionService.on_tick(100)
  end

  test "on_tick enqueues at 200" do
    ProcessReflectionsJob.expects(:perform_async).with(200)
    ReflectionService.on_tick(200)
  end

  test "on_tick does not enqueue between intervals" do
    ProcessReflectionsJob.expects(:perform_async).never
    ReflectionService.on_tick(50)
  end

  test "on_tick does not enqueue at tick 0" do
    ProcessReflectionsJob.expects(:perform_async).never
    ReflectionService.on_tick(0)
  end

  # --- reflect_for_agent: location pattern ---

  test "generates reflection for frequent location visits" do
    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Saw something at market #{i}",
        importance: 3, tick: 10 + i, location: @market
      )
    end

    assert_difference "Memory.where(agent: @alice, memory_type: 'reflection').count" do
      ReflectionService.reflect_for_agent(agent: @alice, tick: 100)
    end

    reflection = @alice.memories.reflection_type.order(created_at: :desc).first
    assert_match(/Market/, reflection.content)
    assert_equal 7, reflection.importance
  end

  # --- reflect_for_agent: agent interaction pattern ---

  test "generates reflection for frequent agent interactions" do
    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Talked to Bob #{i}",
        importance: 5, tick: 10 + i, related_agent_ids: [ @bob.id ]
      )
    end

    assert_difference "Memory.where(agent: @alice, memory_type: 'reflection').count" do
      ReflectionService.reflect_for_agent(agent: @alice, tick: 100)
    end

    reflection = @alice.memories.reflection_type.order(created_at: :desc).first
    assert_match(/Bob/, reflection.content)
    assert_equal 7, reflection.importance
  end

  # --- reflect_for_agent: marks observations ---

  test "marks source observations as reflected_upon" do
    # Clear existing fixture observations
    @alice.memories.observations.update_all(reflected_upon: true)

    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Market visit #{i}",
        importance: 3, tick: 10 + i, location: @market
      )
    end

    ReflectionService.reflect_for_agent(agent: @alice, tick: 100)

    assert_equal 0, @alice.memories.observations.unreflected.count
  end

  # --- reflect_for_agent: emits events ---

  test "emits reflection_created events with source system" do
    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Market thing #{i}",
        importance: 3, tick: 10 + i, location: @market
      )
    end

    assert_difference "Event.where(event_type: 'reflection_created').count" do
      ReflectionService.reflect_for_agent(agent: @alice, tick: 100)
    end

    event = Event.where(event_type: "reflection_created", agent: @alice).order(created_at: :desc).first
    assert_equal "system", event.payload["source"]
  end

  # --- reflect_for_agent: skip conditions ---

  test "skips agents with fewer than 5 unreflected observations" do
    @alice.memories.observations.update_all(reflected_upon: true)

    2.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Something #{i}",
        importance: 3, tick: 10 + i, location: @market
      )
    end

    assert_no_difference "Memory.where(agent: @alice, memory_type: 'reflection').count" do
      ReflectionService.reflect_for_agent(agent: @alice, tick: 100)
    end
  end

  test "skips agents whose observations are already reflected" do
    @alice.memories.observations.update_all(reflected_upon: true)

    assert_no_difference "Memory.where(agent: @alice, memory_type: 'reflection').count" do
      ReflectionService.reflect_for_agent(agent: @alice, tick: 100)
    end
  end

  # --- reflect_for_agent: caps ---

  test "caps at 2 reflections per agent per cycle" do
    @alice.memories.observations.update_all(reflected_upon: true)

    # Create observations hitting both patterns
    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Market interaction #{i}",
        importance: 5, tick: 10 + i,
        location: @market,
        related_agent_ids: [ @bob.id ]
      )
    end

    ReflectionService.reflect_for_agent(agent: @alice, tick: 100)

    assert @alice.memories.reflection_type.count <= 2
  end
end
