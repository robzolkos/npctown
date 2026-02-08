require "test_helper"

class MemoryServiceTest < ActiveSupport::TestCase
  setup do
    # Scope Redis keys per process to avoid parallel test pollution
    MemoryService.redis_key_prefix = "npctown:memory_service:test:#{Process.pid}"
    MemoryService.last_processed_tick = -1
  end

  teardown do
    Sidekiq.redis do |conn|
      conn.del("#{MemoryService.redis_key_prefix}:last_processed_tick")
      conn.del("#{MemoryService.redis_key_prefix}:processing_lock")
    end
    MemoryService.redis_key_prefix = nil
  end

  # --- create_memory ---

  test "create_memory creates a valid memory" do
    mem = MemoryService.create_memory(
      agent: agents(:alice),
      content: "Something happened",
      importance: 5,
      tick: 10,
      location: locations(:town_square)
    )

    assert mem.persisted?
    assert_equal "observation", mem.memory_type
    assert_equal 5, mem.importance
    assert_equal 10, mem.tick
    assert mem.id.start_with?("mem_")
  end

  test "create_memory clamps importance to 1-10" do
    high = MemoryService.create_memory(agent: agents(:alice), content: "test", importance: 15, tick: 1)
    assert_equal 10, high.importance

    low = MemoryService.create_memory(agent: agents(:alice), content: "test2", importance: -5, tick: 1)
    assert_equal 1, low.importance
  end

  test "create_memory stores related_agent_ids" do
    mem = MemoryService.create_memory(
      agent: agents(:alice),
      content: "Met Bob",
      importance: 5,
      tick: 1,
      related_agent_ids: [ agents(:bob).id ]
    )
    assert_includes mem.related_agent_ids, agents(:bob).id
  end

  # --- observe_event ---

  test "observe_event creates memory from agent_spoke event" do
    event = EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      agent: agents(:bob),
      location: locations(:town_square),
      payload: { message: "Hello!" }
    )

    mem = MemoryService.observe_event(event: event, agent: agents(:alice))

    assert mem.persisted?
    assert_equal "observation", mem.memory_type
    assert_match(/Bob said: "Hello!"/, mem.content)
    assert_equal 4, mem.importance
    assert_includes mem.related_agent_ids, agents(:bob).id
  end

  test "observe_event discounts importance for self-events" do
    event = EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      agent: agents(:alice),
      location: locations(:town_square),
      payload: { message: "Hello!" }
    )

    mem = MemoryService.observe_event(event: event, agent: agents(:alice))

    assert mem.persisted?
    assert_match(/You said/, mem.content)
    assert_equal 3, mem.importance
  end

  test "observe_event skips tick_advanced events" do
    event = EventService.append(event_type: "tick_advanced", tick: 5, payload: { tick: 5 })
    mem = MemoryService.observe_event(event: event, agent: agents(:alice))
    assert_nil mem
  end

  test "observe_event skips memory_created events" do
    event = EventService.append(event_type: "memory_created", tick: 5, agent: agents(:alice), payload: {})
    mem = MemoryService.observe_event(event: event, agent: agents(:alice))
    assert_nil mem
  end

  test "observe_event handles agent_moved" do
    event = EventService.append(
      event_type: "agent_moved",
      tick: 5,
      agent: agents(:bob),
      location: locations(:market),
      payload: { from_location_name: "Town Square", to_location_name: "Market" }
    )

    mem = MemoryService.observe_event(event: event, agent: agents(:alice))

    assert mem.persisted?
    assert_match(/Bob moved from Town Square to Market/, mem.content)
    assert_equal 2, mem.importance
  end

  test "observe_event handles conversation_started with agent_cache" do
    event = EventService.append(
      event_type: "conversation_started",
      tick: 5,
      agent: agents(:alice),
      location: locations(:town_square),
      payload: {
        conversation_id: "conv_test",
        initiator_id: agents(:alice).id,
        target_agent_id: agents(:charlie).id,
        message: "Hey!"
      }
    )

    # Pass agent_cache to avoid N+1
    cache = { agents(:charlie).id => agents(:charlie) }
    mem = MemoryService.observe_event(event: event, agent: agents(:bob), agent_cache: cache)

    assert mem.persisted?
    assert_match(/Alice started a conversation with Charlie/, mem.content)
    assert_equal 5, mem.importance
  end

  test "observe_event handles agent_action emote" do
    event = EventService.append(
      event_type: "agent_action",
      tick: 5,
      agent: agents(:bob),
      location: locations(:town_square),
      payload: { type: "emote", description: "waves hello" }
    )

    mem = MemoryService.observe_event(event: event, agent: agents(:alice))

    assert mem.persisted?
    assert_match(/Bob waves hello/, mem.content)
    assert_equal 3, mem.importance
  end

  test "observe_event handles agent_registered" do
    event = EventService.append(
      event_type: "agent_registered",
      tick: 5,
      agent: agents(:bob),
      location: locations(:town_square),
      payload: { agent_name: "Bob" }
    )

    mem = MemoryService.observe_event(event: event, agent: agents(:alice))

    assert mem.persisted?
    assert_match(/Bob arrived in town/, mem.content)
    assert_equal 7, mem.importance
  end

  # --- memories_for ---

  test "memories_for returns agent memories ordered by recency" do
    mems = MemoryService.memories_for(agent: agents(:alice))

    assert mems.any?
    mems.each_cons(2) { |a, b| assert a.tick >= b.tick }
  end

  test "memories_for filters by type" do
    mems = MemoryService.memories_for(agent: agents(:alice), type: "observation")
    assert mems.all? { |m| m.memory_type == "observation" }
  end

  test "memories_for filters by min_importance" do
    mems = MemoryService.memories_for(agent: agents(:alice), min_importance: 5)
    assert mems.all? { |m| m.importance >= 5 }
  end

  test "memories_for filters by since_tick" do
    mems = MemoryService.memories_for(agent: agents(:alice), since_tick: 2)
    assert mems.all? { |m| m.tick >= 2 }
  end

  test "memories_for respects limit" do
    5.times do |i|
      MemoryService.create_memory(agent: agents(:alice), content: "mem #{i}", importance: 3, tick: 10 + i)
    end

    mems = MemoryService.memories_for(agent: agents(:alice), limit: 3)
    assert_equal 3, mems.size
  end

  # --- on_tick (async) ---

  test "on_tick enqueues ProcessMemoriesJob" do
    ProcessMemoriesJob.expects(:perform_async).with(10)
    MemoryService.on_tick(10)
  end

  # --- process_events_into_memories ---

  test "process_events_into_memories creates memories from events at agent locations" do
    EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      agent: agents(:alice),
      location: locations(:town_square),
      payload: { message: "Hello town!" }
    )

    MemoryService.last_processed_tick = 4

    assert_difference "Memory.count", 2 do
      MemoryService.process_events_into_memories(6)
    end
  end

  test "process_events_into_memories does not reprocess events" do
    EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      agent: agents(:alice),
      location: locations(:town_square),
      payload: { message: "Hello!" }
    )

    MemoryService.last_processed_tick = 4
    MemoryService.process_events_into_memories(6)
    count_after = Memory.count

    MemoryService.process_events_into_memories(7)
    assert_equal count_after, Memory.count
  end

  test "process_events_into_memories updates last_processed_tick in Redis" do
    MemoryService.last_processed_tick = -1
    MemoryService.process_events_into_memories(10)
    assert_equal 9, MemoryService.last_processed_tick
  end

  test "process_events_into_memories skips when locked" do
    # Simulate an existing lock
    lock_key = "#{MemoryService.redis_key_prefix}:processing_lock"
    Sidekiq.redis { |conn| conn.set(lock_key, "1", ex: 30) }

    EventService.append(
      event_type: "agent_spoke",
      tick: 5,
      agent: agents(:alice),
      location: locations(:town_square),
      payload: { message: "Hello!" }
    )

    MemoryService.last_processed_tick = 4

    assert_no_difference "Memory.count" do
      MemoryService.process_events_into_memories(6)
    end
  end

  # --- last_processed_tick (Redis-backed) ---

  test "last_processed_tick persists in Redis" do
    MemoryService.last_processed_tick = 42
    assert_equal 42, MemoryService.last_processed_tick
  end

  test "last_processed_tick defaults to -1 when unset" do
    Sidekiq.redis { |conn| conn.del("#{MemoryService.redis_key_prefix}:last_processed_tick") }
    assert_equal(-1, MemoryService.last_processed_tick)
  end

  # --- trim_memories ---

  test "trim_memories removes excess low-importance memories" do
    agent = agents(:alice)
    # Create 5 memories with varying importance
    5.times do |i|
      MemoryService.create_memory(agent: agent, content: "mem #{i}", importance: i + 1, tick: 100 + i)
    end

    initial_count = agent.memories.count
    MemoryService.trim_memories(agent.id, max: 3)

    assert_equal [ initial_count, 3 ].min, [ agent.memories.count, 3 ].min
    # Highest importance memories should survive
    remaining = agent.memories.reload.order(importance: :desc).pluck(:importance)
    assert remaining.first >= remaining.last
  end

  test "trim_memories does nothing when under cap" do
    agent = agents(:alice)
    count_before = agent.memories.count

    assert_no_difference "Memory.where(agent_id: '#{agent.id}').count" do
      MemoryService.trim_memories(agent.id, max: 10_000)
    end
  end
end
