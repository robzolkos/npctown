class WorldService
  class MovementError < StandardError; end

  MVP_LOCATIONS = [
    {
      name: "Town Square",
      description: "The bustling heart of town. A large open plaza with a weathered stone fountain " \
                   "at its center, surrounded by worn wooden benches and cork notice boards pinned " \
                   "with flyers and announcements. Cobblestone paths branch out in every direction. " \
                   "Agents gather here to socialize, share news, and watch the world go by. " \
                   "The atmosphere is lively and open — a place to be seen.",
      location_type: "social"
    },
    {
      name: "Market",
      description: "A lively marketplace beneath colorful canvas awnings. Wooden stalls line both " \
                   "sides of a wide dirt path, selling everything from fresh bread to rare curiosities. " \
                   "The air is thick with the sounds of bartering, clinking coins, and the smell of " \
                   "roasting nuts. Agents come here to trade resources, strike deals, and size up the " \
                   "competition. Fortunes are made and lost in the span of a conversation.",
      location_type: "commerce"
    },
    {
      name: "Library",
      description: "A quiet, grand stone building with tall arched windows that let in soft natural " \
                   "light. Floor-to-ceiling shelves hold books, scrolls, and maps. Heavy oak tables " \
                   "sit in rows, and the only sounds are the rustle of turning pages and the occasional " \
                   "whispered exchange. Agents come here to reflect, study, plan, and have thoughtful " \
                   "conversations. The atmosphere encourages deep thinking and careful deliberation.",
      location_type: "knowledge"
    }
  ].freeze

  # Move an agent to a new location, emitting an agent_moved event.
  def self.move_agent(agent:, location:, tick:)
    validate_move!(agent, location)

    from_location = agent.location

    agent.update!(location: location)

    EventService.append(
      event_type: "agent_moved",
      tick: tick,
      agent: agent,
      location: location,
      payload: {
        from_location_id: from_location&.id,
        from_location_name: from_location&.name,
        to_location_id: location.id,
        to_location_name: location.name
      }
    )
  end

  # Get all agents currently at a location.
  def self.agents_at(location)
    Agent.at_location(location)
  end

  # Get the location for a specific agent.
  def self.location_for(agent)
    agent.location
  end

  # Ensure the three MVP locations exist. Idempotent.
  def self.setup_world
    MVP_LOCATIONS.map do |attrs|
      Location.find_or_create_by!(name: attrs[:name]) do |loc|
        loc.description = attrs[:description]
        loc.location_type = attrs[:location_type]
      end
    end
  end

  def self.validate_move!(agent, location)
    raise MovementError, "Agent is already at #{location.name}" if agent.location_id == location.id
  end
  private_class_method :validate_move!
end
