class StaminaService
  REGEN_INTERVAL = 180 # grant +1 stamina every 180 ticks (~4/hour at 5s ticks)
  MAX_STAMINA = 100
  REDIS_KEY = "npctown:stamina:regen_counter"

  class << self
    attr_writer :redis_key

    def redis_key
      @redis_key || REDIS_KEY
    end
  end

  def self.on_tick(_tick)
    counter = Sidekiq.redis { |c| c.incr(redis_key) }

    return unless counter >= REGEN_INTERVAL

    Sidekiq.redis { |c| c.set(redis_key, 0) }

    Agent.active.where("stamina < ?", MAX_STAMINA).find_each do |agent|
      new_stamina = [ agent.stamina + 1, MAX_STAMINA ].min
      agent.update_column(:stamina, new_stamina)
    end
  end

  def self.name
    "StaminaService"
  end
end
