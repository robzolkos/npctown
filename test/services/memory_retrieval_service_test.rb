require "test_helper"

class MemoryRetrievalServiceTest < ActiveSupport::TestCase
  setup do
    # Fixtures bypass the database trigger, so backfill search_vector for tests
    Memory.connection.execute("UPDATE memories SET search_vector = to_tsvector('english', content) WHERE search_vector IS NULL")

    # Set a known current tick so recency scoring works predictably
    EventService.append(event_type: "tick_advanced", tick: 100, payload: {})
  end

  # --- get_relevant_memories ---

  test "get_relevant_memories with query ranks relevant memories higher" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: "trading merchants", limit: 5)

    assert results.any?
    # The trading/merchant memory should be near the top
    top_content = results.first.content
    assert_match(/trad|merchant|haggl/i, top_content)
  end

  test "get_relevant_memories without query falls back to recency and importance" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: nil, limit: 5)

    assert results.any?
    # Without a query, relevance is 0 for all — ranking uses recency + importance
    # alice_high_importance (tick 2, importance 7) should rank high
    assert results.any? { |m| m.id == memories(:alice_high_importance).id }
  end

  test "get_relevant_memories with blank query treats as no query" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: "", limit: 5)

    assert results.any?
  end

  test "recency scoring favors recent memories" do
    alice = agents(:alice)
    # Create a memory at the current tick (100) — much more recent than fixtures at tick 1-2
    recent = MemoryService.create_memory(
      agent: alice, content: "Something just happened at the Library.",
      importance: 3, tick: 100, location: locations(:library)
    )
    # Backfill search_vector for the new memory
    Memory.connection.execute("UPDATE memories SET search_vector = to_tsvector('english', content) WHERE search_vector IS NULL")

    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: nil, limit: 10)

    # The recent memory (tick 100) should rank above old fixture memories (tick 1-2)
    assert_equal recent.id, results.first.id
  end

  test "importance scoring favors high-importance memories" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: nil, limit: 10)

    # alice_high_importance (importance 7, tick 2) should rank above alice_observation (importance 3, tick 1)
    high_idx = results.index { |m| m.id == memories(:alice_high_importance).id }
    low_idx = results.index { |m| m.id == memories(:alice_observation).id }

    assert_not_nil high_idx
    assert_not_nil low_idx
    assert high_idx < low_idx, "High-importance memory should rank above low-importance"
  end

  test "relevance can boost old memories above recent ones" do
    alice = agents(:alice)
    # alice_old_market_memory is tick 1 (old) but highly relevant to "trading"
    # alice_library_memory is tick 2 (more recent) but about "books"
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: "trading goods", limit: 5)

    market_idx = results.index { |m| m.id == memories(:alice_old_market_memory).id }
    library_idx = results.index { |m| m.id == memories(:alice_library_memory).id }

    assert_not_nil market_idx, "Market memory should appear in results"
    # Library memory may or may not appear, but market should rank higher if both present
    if library_idx
      assert market_idx < library_idx, "Relevant old memory should rank above irrelevant newer one"
    end
  end

  test "get_relevant_memories respects limit" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_relevant_memories(agent: alice, query: nil, limit: 2)

    assert_equal 2, results.length
  end

  test "get_relevant_memories returns empty for agent with no memories" do
    charlie = agents(:charlie)
    results = MemoryRetrievalService.get_relevant_memories(agent: charlie, query: "anything", limit: 10)

    assert_empty results
  end

  # --- Helper: get_recent_memories ---

  test "get_recent_memories returns memories ordered by tick desc" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_recent_memories(agent: alice, limit: 10)

    assert results.any?
    ticks = results.map(&:tick)
    assert_equal ticks.sort.reverse, ticks
  end

  test "get_recent_memories respects limit" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_recent_memories(agent: alice, limit: 2)

    assert_equal 2, results.length
  end

  # --- Helper: get_memories_about_agent ---

  test "get_memories_about_agent returns memories mentioning target" do
    alice = agents(:alice)
    bob = agents(:bob)
    results = MemoryRetrievalService.get_memories_about_agent(agent: alice, target_agent_id: bob.id, limit: 10)

    assert results.any?
    results.each do |memory|
      assert_includes memory.related_agent_ids, bob.id
    end
  end

  test "get_memories_about_agent returns empty when no mentions" do
    alice = agents(:alice)
    charlie = agents(:charlie)
    results = MemoryRetrievalService.get_memories_about_agent(agent: alice, target_agent_id: charlie.id, limit: 10)

    assert_empty results
  end

  # --- Helper: get_memories_at_location ---

  test "get_memories_at_location filters by location" do
    alice = agents(:alice)
    market = locations(:market)
    results = MemoryRetrievalService.get_memories_at_location(agent: alice, location: market, limit: 10)

    assert results.any?
    results.each do |memory|
      assert_equal market.id, memory.location_id
    end
  end

  test "get_memories_at_location accepts location id string" do
    alice = agents(:alice)
    results = MemoryRetrievalService.get_memories_at_location(agent: alice, location: locations(:market).id, limit: 10)

    assert results.any?
  end

  test "get_memories_at_location returns empty for unvisited location" do
    bob = agents(:bob)
    library = locations(:library)
    results = MemoryRetrievalService.get_memories_at_location(agent: bob, location: library, limit: 10)

    assert_empty results
  end
end
