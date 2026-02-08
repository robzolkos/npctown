class StaminaService
  REGEN_PER_TICK = 2
  MAX_STAMINA = 100

  def self.on_tick(_tick)
    Agent.active.where("stamina < ?", MAX_STAMINA).find_each do |agent|
      new_stamina = [ agent.stamina + REGEN_PER_TICK, MAX_STAMINA ].min
      agent.update_column(:stamina, new_stamina)
    end
  end

  def self.name
    "StaminaService"
  end
end
