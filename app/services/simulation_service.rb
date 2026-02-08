class SimulationService
  class SimulationError < StandardError; end

  REDIS_STATE_KEY = "npctown:simulation:state"
  TICK_LOCK_KEY = "npctown:tick_lock"
  TICK_LOCK_TTL = 4
  DEFAULT_STATE = "stopped"

  # --- Tick listeners registry ---

  @listeners = []
  @redis_state_key = nil
  @tick_lock_key = nil

  class << self
    attr_reader :listeners
    attr_writer :redis_state_key, :tick_lock_key

    def redis_state_key
      @redis_state_key || REDIS_STATE_KEY
    end

    def tick_lock_key
      @tick_lock_key || TICK_LOCK_KEY
    end
  end

  def self.register_listener(listener)
    @listeners << listener unless @listeners.include?(listener)
  end

  def self.clear_listeners
    @listeners = []
  end

  # --- State management ---

  def self.state
    Sidekiq.redis { |conn| conn.get(redis_state_key) } || DEFAULT_STATE
  end

  def self.running?
    state == "running"
  end

  def self.paused?
    state == "paused"
  end

  def self.stopped?
    state == "stopped"
  end

  def self.start
    set_state("running")
  end

  def self.stop
    set_state("stopped")
  end

  def self.pause
    raise SimulationError, "Cannot pause unless running" unless running?

    set_state("paused")
  end

  def self.resume
    raise SimulationError, "Cannot resume unless paused" unless paused?

    set_state("running")
  end

  # --- Tick operations ---

  def self.current_tick
    Event.of_type("tick_advanced").maximum(:tick) || 0
  end

  def self.tick!
    return unless running?

    # Only one tick per interval, safe across any number of processes
    lock_acquired = Sidekiq.redis { |c| c.set(tick_lock_key, "1", nx: true, ex: TICK_LOCK_TTL) }
    return unless lock_acquired

    new_tick = current_tick + 1

    EventService.append(
      event_type: "tick_advanced",
      tick: new_tick,
      payload: { tick: new_tick }
    )

    notify_listeners(new_tick)

    new_tick
  end

  # --- Private ---

  def self.notify_listeners(tick)
    listeners.each do |listener|
      listener.on_tick(tick)
    rescue => e
      Rails.logger.error("[SimulationService] Listener #{listener.name} failed on tick #{tick}: #{e.message}")
    end
  end
  private_class_method :notify_listeners

  def self.set_state(new_state)
    Sidekiq.redis { |conn| conn.set(redis_state_key, new_state) }
  end
  private_class_method :set_state
end
