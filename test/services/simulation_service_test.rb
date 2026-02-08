require "test_helper"

class SimulationServiceTest < ActiveSupport::TestCase
  setup do
    SimulationService.clear_listeners
    SimulationService.stop_timer
    # Scope Redis key per process to avoid parallel test pollution
    SimulationService.redis_state_key = "npctown:simulation:state:test:#{Process.pid}"
    Sidekiq.redis { |conn| conn.del(SimulationService.redis_state_key) }
  end

  teardown do
    SimulationService.stop_timer
    Sidekiq.redis { |conn| conn.del(SimulationService.redis_state_key) }
    SimulationService.redis_state_key = nil
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
    t2 = SimulationService.tick!
    t3 = SimulationService.tick!

    assert_equal 2, t1
    assert_equal 3, t2
    assert_equal 4, t3
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

  # --- Timer management ---

  test "start creates a running timer" do
    SimulationService.start
    assert SimulationService.timer_running?
  end

  test "stop shuts down the timer" do
    SimulationService.start
    assert SimulationService.timer_running?

    SimulationService.stop
    assert_not SimulationService.timer_running?
  end

  test "timer fires tick! automatically" do
    SimulationService.start
    initial_tick = SimulationService.current_tick

    # Replace timer with a fast one
    SimulationService.stop_timer
    task = Concurrent::TimerTask.new(execution_interval: 0.1) do
      SimulationService.tick!
    end
    task.execute
    sleep 0.8
    task.shutdown

    assert SimulationService.current_tick > initial_tick, "Timer should have advanced the tick"
  end
end
