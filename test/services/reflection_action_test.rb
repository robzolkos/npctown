require "test_helper"

class ReflectionActionTest < ActiveSupport::TestCase
  setup do
    @alice = agents(:alice)
    @bob = agents(:bob)
    @market = locations(:market)
  end

  test "reflect action creates a reflection memory with importance 9" do
    assert_difference "Memory.where(agent: @alice, memory_type: 'reflection').count" do
      ActionService.execute(
        agent: @alice,
        action_type: "reflect",
        params: { content: "I seem to enjoy the Market." }
      )
    end

    reflection = @alice.memories.reflection_type.last
    assert_equal "I seem to enjoy the Market.", reflection.content
    assert_equal 9, reflection.importance
    assert_equal "reflection", reflection.memory_type
  end

  test "reflect action marks unreflected observations as reflected_upon" do
    5.times do |i|
      MemoryService.create_memory(
        agent: @alice, content: "Observation #{i}", importance: 3, tick: 10 + i, location: @market
      )
    end

    assert @alice.memories.observations.unreflected.count >= 5

    ActionService.execute(
      agent: @alice,
      action_type: "reflect",
      params: { content: "I notice patterns at the Market." }
    )

    assert_equal 0, @alice.memories.observations.unreflected.count
  end

  test "reflect action emits reflection_created event with source agent" do
    assert_difference "Event.where(event_type: 'reflection_created').count" do
      ActionService.execute(
        agent: @alice,
        action_type: "reflect",
        params: { content: "I like exploring." }
      )
    end

    event = Event.where(event_type: "reflection_created", agent: @alice).order(created_at: :desc).first
    assert_equal "agent", event.payload["source"]
    assert_equal "I like exploring.", event.payload["content"]
  end

  test "reflect action with blank content returns error" do
    assert_raises(ActionService::ActionError) do
      ActionService.execute(
        agent: @alice,
        action_type: "reflect",
        params: { content: "" }
      )
    end
  end

  test "reflect action costs 0 stamina" do
    stamina_before = @alice.stamina

    ActionService.execute(
      agent: @alice,
      action_type: "reflect",
      params: { content: "Thinking about things." }
    )

    @alice.reload
    assert_equal stamina_before, @alice.stamina
  end

  test "reflect action works with no unreflected observations" do
    @alice.memories.observations.update_all(reflected_upon: true)

    assert_nothing_raised do
      ActionService.execute(
        agent: @alice,
        action_type: "reflect",
        params: { content: "A general thought." }
      )
    end

    assert_equal 1, @alice.memories.reflection_type.count
  end
end
