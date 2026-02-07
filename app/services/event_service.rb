class EventService
  class InvalidEventType < StandardError; end

  # Append a new event to the log
  def self.append(event_type:, tick:, payload: {}, agent: nil, location: nil)
    unless Event::TYPES.include?(event_type)
      raise InvalidEventType, "Unknown event type: #{event_type}"
    end

    Event.create!(
      event_type: event_type,
      tick: tick,
      payload: payload,
      agent: agent,
      location: location
    )
  end

  # Query events with flexible filters
  def self.query(event_type: nil, since_tick: nil, agent: nil, location: nil, limit: 50)
    scope = Event.chronological

    scope = scope.of_type(event_type) if event_type
    scope = scope.since_tick(since_tick) if since_tick
    scope = scope.for_agent(agent) if agent
    scope = scope.at_location(location) if location

    scope.limit(limit)
  end

  # Get all events since a specific tick
  def self.since(tick, limit: 100)
    Event.since_tick(tick).chronological.limit(limit)
  end

  # Get recent events at a location
  def self.at_location(location, since_tick: nil, limit: 50)
    scope = Event.at_location(location).chronological
    scope = scope.since_tick(since_tick) if since_tick
    scope.limit(limit)
  end
end
