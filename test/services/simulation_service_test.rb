require "test_helper"

class SimulationServiceTest < ActiveSupport::TestCase
  setup do
    SimulationService.clear_listeners
    # Scope Redis keys per process to avoid parallel test pollution
    SimulationService.redis_state_key = "npctown:simulation:state:test:#{Process.pid}"
    SimulationService.tick_lock_key = "npctown:tick_lock:test:#{Process.pid}"
    Sidekiq.redis { |conn| conn.del(SimulationService.redis_state_key) }
    Sidekiq.redis { |conn| conn.del(SimulationService.tick_lock_key) }
  end

  teardown do
    Sidekiq.redis { |conn| conn.del(SimulationService.redis_state_key) }
    Sidekiq.redis { |conn| conn.del(SimulationService.tick_lock_key) }
    SimulationService.redis_state_key = nil
    SimulationService.tick_lock_key = nil
  end

  # --- State management ---

  test "default state is stopped" do
    assert_equal "stopped", SimulationService.state
    assert SimulationService.stopped?
    assert_not SimulationService.running?
    assert_not SimulationService.paused?
  end

  test "start sets state to running" do
    SimulationService.start
    assert SimulationService.running?
  end

  test "stop sets state to stopped" do
    SimulationService.start
    SimulationService.stop
    assert SimulationService.stopped?
  end

  test "pause sets state to paused when running" do
    SimulationService.start
    SimulationService.pause
    assert SimulationService.paused?
  end

  test "pause raises when not running" do
    assert_raises(SimulationService::SimulationError) do
      SimulationService.pause
    end
  end

  test "resume sets state to running when paused" do
    SimulationService.start
    SimulationService.pause
    SimulationService.resume
    assert SimulationService.running?
  end

  test "resume raises when not paused" do
    SimulationService.start
    assert_raises(SimulationService::SimulationError) do
      SimulationService.resume
    end
  end

  # --- Tick operations ---

  test "current_tick returns 0 with no tick events" do
    Event.of_type("tick_advanced").delete_all
    assert_equal 0, SimulationService.current_tick
  end

  test "current_tick returns max tick from tick_advanced events" do
    # fixture tick_one has tick: 1
    assert_equal 1, SimulationService.current_tick
  end

  test "tick! advances tick and emits event" do
    SimulationService.start

    assert_difference "Event.count", 1 do
      new_tick = SimulationService.tick!
      assert_equal 2, new_tick
    end

    event = Event.of_type("tick_advanced").order(tick: :desc).first
    assert_equal 2, event.tick
    assert_equal({ "tick" => 2 }, event.payload)
  end

  test "tick! returns nil when stopped" do
    assert_nil SimulationService.tick!
  end

  test "tick! skips when paused" do
    SimulationService.start
    SimulationService.pause

    assert_no_difference "Event.count" do
      assert_nil SimulationService.tick!
    end
  end

  test "multiple ticks increment sequentially" do
    SimulationService.start

    t1 = SimulationService.tick!
    Sidekiq.redis { |conn| conn.del(SimulationService.tick_lock_key) }
    t2 = SimulationService.tick!
    Sidekiq.redis { |conn| conn.del(SimulationService.tick_lock_key) }
    t3 = SimulationService.tick!

    assert_equal 2, t1
    assert_equal 3, t2
    assert_equal 4, t3
  end

  test "tick! is guarded by SETNX lock" do
    SimulationService.start

    assert_equal 2, SimulationService.tick!
    # Second tick blocked by lock
    assert_nil SimulationService.tick!
  end

  # --- Listeners ---

  test "tick! notifies registered listeners" do
    SimulationService.start

    listener = mock("listener")
    listener.expects(:on_tick).with(2)

    SimulationService.register_listener(listener)
    SimulationService.tick!
  end

  test "listener failure does not halt tick" do
    SimulationService.start

    bad_listener = mock("bad_listener")
    bad_listener.stubs(:name).returns("BadListener")
    bad_listener.expects(:on_tick).raises(RuntimeError, "boom")

    good_listener = mock("good_listener")
    good_listener.expects(:on_tick).with(2)

    SimulationService.register_listener(bad_listener)
    SimulationService.register_listener(good_listener)

    # Should not raise
    SimulationService.tick!
  end

  test "register_listener does not add duplicates" do
    listener = mock("listener")
    SimulationService.register_listener(listener)
    SimulationService.register_listener(listener)

    assert_equal 1, SimulationService.listeners.count
  end
end
