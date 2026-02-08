class ResourceService
  # Decay rates
  ENERGY_DECAY_INTERVAL = 10    # -1 energy every 10 ticks
  FOOD_DECAY_INTERVAL = 20      # -1 food every 20 ticks

  # Market bonus
  MARKET_BONUS_INTERVAL = 720   # every 720 ticks (~1 hour at 5s ticks)
  MARKET_FOOD_BONUS = 10
  MARKET_CURRENCY_BONUS = 10

  # Action values
  REST_ENERGY_RESTORE = 30
  EAT_FOOD_COST = 20
  EAT_ENERGY_RESTORE = 40
  TRADE_MAX_AMOUNT = 50

  # Starvation multiplier
  STARVATION_ENERGY_MULTIPLIER = 2

  def self.on_tick(tick)
    decay_energy(tick) if (tick % ENERGY_DECAY_INTERVAL).zero?
    decay_food(tick) if (tick % FOOD_DECAY_INTERVAL).zero?
    apply_market_bonus(tick) if (tick % MARKET_BONUS_INTERVAL).zero?
  end

  def self.name
    "ResourceService"
  end

  def self.rest(agent:, tick:)
    previous_energy = agent.energy
    new_energy = [ agent.energy + REST_ENERGY_RESTORE, 100 ].min
    agent.update!(energy: new_energy)

    EventService.append(
      event_type: "resource_changed",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: {
        reason: "rest",
        changes: { energy: { previous: previous_energy, current: new_energy } }
      }
    )
  end

  def self.eat(agent:, tick:)
    raise ActionService::ActionError, "Not enough food to eat" if agent.food < EAT_FOOD_COST

    previous_food = agent.food
    previous_energy = agent.energy
    new_food = agent.food - EAT_FOOD_COST
    new_energy = [ agent.energy + EAT_ENERGY_RESTORE, 100 ].min

    agent.update!(food: new_food, energy: new_energy)

    EventService.append(
      event_type: "resource_changed",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: {
        reason: "eat",
        changes: {
          food: { previous: previous_food, current: new_food },
          energy: { previous: previous_energy, current: new_energy }
        }
      }
    )
  end

  def self.trade(agent:, target:, resource:, amount:, tick:)
    raise ActionService::ActionError, "Invalid resource" unless %w[food energy currency].include?(resource)
    raise ActionService::ActionError, "Amount must be positive" unless amount.positive?
    raise ActionService::ActionError, "Amount exceeds maximum (#{TRADE_MAX_AMOUNT})" if amount > TRADE_MAX_AMOUNT
    raise ActionService::ActionError, "Must be at the same location" unless agent.location_id == target.location_id
    raise ActionService::ActionError, "Insufficient #{resource}" if agent.send(resource) < amount

    previous_giver = agent.send(resource)
    previous_receiver = target.send(resource)

    agent.update!(resource => agent.send(resource) - amount)
    target.update!(resource => target.send(resource) + amount)

    EventService.append(
      event_type: "resource_changed",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: {
        reason: "trade",
        target_agent_id: target.id,
        resource: resource,
        amount: amount,
        giver: { previous: previous_giver, current: agent.send(resource) },
        receiver: { previous: previous_receiver, current: target.send(resource) }
      }
    )
  end

  # --- Perception helpers ---

  def self.resource_description(agent)
    [ food_label(agent.food), energy_label(agent.energy), wealth_label(agent.currency) ]
  end

  # --- Private ---

  def self.decay_energy(tick)
    Agent.active.where("energy > 0").find_each do |agent|
      decay = agent.food == 0 ? STARVATION_ENERGY_MULTIPLIER : 1
      new_energy = [ agent.energy - decay, 0 ].max
      agent.update_column(:energy, new_energy)

      if new_energy == 0
        EventService.append(
          event_type: "resource_changed",
          tick: tick,
          agent: agent,
          location: agent.location,
          payload: { reason: "exhausted", energy: 0 }
        )
      end
    end
  end
  private_class_method :decay_energy

  def self.decay_food(tick)
    Agent.active.where("food > 0").find_each do |agent|
      new_food = [ agent.food - 1, 0 ].max
      agent.update_column(:food, new_food)

      if new_food == 0
        EventService.append(
          event_type: "resource_changed",
          tick: tick,
          agent: agent,
          location: agent.location,
          payload: { reason: "starving", food: 0 }
        )
      end
    end
  end
  private_class_method :decay_food

  def self.apply_market_bonus(tick)
    Location.by_type("commerce").each do |location|
      Agent.active.where(location: location).find_each do |agent|
        previous_food = agent.food
        previous_currency = agent.currency
        agent.update!(
          food: agent.food + MARKET_FOOD_BONUS,
          currency: agent.currency + MARKET_CURRENCY_BONUS
        )

        EventService.append(
          event_type: "resource_changed",
          tick: tick,
          agent: agent,
          location: location,
          payload: {
            reason: "market_bonus",
            changes: {
              food: { previous: previous_food, current: agent.food },
              currency: { previous: previous_currency, current: agent.currency }
            }
          }
        )
      end
    end
  end
  private_class_method :apply_market_bonus

  def self.food_label(food)
    if food <= 10 then "starving"
    elsif food <= 30 then "hungry"
    elsif food <= 60 then "fed"
    else "well-fed"
    end
  end
  private_class_method :food_label

  def self.energy_label(energy)
    if energy == 0 then "exhausted"
    elsif energy <= 20 then "tired"
    elsif energy <= 50 then "rested"
    else "energetic"
    end
  end
  private_class_method :energy_label

  def self.wealth_label(currency)
    if currency <= 20 then "poor"
    elsif currency <= 100 then "modest"
    elsif currency <= 500 then "comfortable"
    else "wealthy"
    end
  end
  private_class_method :wealth_label
end
