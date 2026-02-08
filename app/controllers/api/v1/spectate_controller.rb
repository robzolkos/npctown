class Api::V1::SpectateController < ActionController::API
  include ActionController::Live

  POLL_INTERVAL = 1 # seconds between DB polls
  HEARTBEAT_INTERVAL = 15 # seconds between heartbeats
  MAX_EVENTS_PER_POLL = 50

  # GET /api/v1/spectate/stream
  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no" # disable nginx buffering

    last_event_id = request.headers["Last-Event-ID"]
    last_seen_id = last_event_id
    last_heartbeat = Time.current

    # If reconnecting with Last-Event-ID, replay from that point
    if last_seen_id.present?
      replay_events(last_seen_id)
    end

    loop do
      events = fetch_new_events(last_seen_id)

      events.each do |event|
        write_sse_event(event)
        last_seen_id = event.id
      end

      # Heartbeat to keep connection alive
      if Time.current - last_heartbeat >= HEARTBEAT_INTERVAL
        response.stream.write(": heartbeat\n\n")
        last_heartbeat = Time.current
      end

      sleep POLL_INTERVAL
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client disconnected — expected
  ensure
    response.stream.close
  end

  # GET /api/v1/spectate/history
  def history
    since_tick = params[:since_tick]&.to_i || 0
    limit = [ (params[:limit]&.to_i || 50), 200 ].min

    scope = Event.where("tick >= ?", since_tick)
                 .where(event_type: SpectatorEventFormatter::SPECTATOR_TYPES)
                 .chronological

    scope = apply_filters(scope)
    events = scope.limit(limit).includes(:agent, :location)

    render json: SpectatorEventFormatter.format_many(events)
  end

  private

  def replay_events(from_event_id)
    # Find the tick of the last-seen event, replay everything after it
    last_event = Event.find_by(id: from_event_id)
    return unless last_event

    events = Event.where("created_at > ?", last_event.created_at)
                  .where(event_type: SpectatorEventFormatter::SPECTATOR_TYPES)
                  .chronological
    events = apply_filters(events)
    events.limit(MAX_EVENTS_PER_POLL).includes(:agent, :location).each do |event|
      write_sse_event(event)
    end
  end

  def fetch_new_events(last_seen_id)
    scope = if last_seen_id.present?
              last_event = Event.find_by(id: last_seen_id)
              if last_event
                Event.where("created_at > ?", last_event.created_at)
              else
                Event.none
              end
    else
              # First connection — start from now (no replay of entire history)
              Event.where("created_at > ?", Time.current)
    end

    scope = scope.where(event_type: SpectatorEventFormatter::SPECTATOR_TYPES)
                 .chronological
    scope = apply_filters(scope)
    scope.limit(MAX_EVENTS_PER_POLL).includes(:agent, :location).to_a
  end

  def apply_filters(scope)
    if params[:location].present?
      location = Location.find_by("LOWER(name) = ?", params[:location].downcase)
      scope = scope.where(location: location) if location
    end

    if params[:agent].present?
      agent = Agent.find_by_prefixed_id(params[:agent])
      scope = scope.where(agent: agent) if agent
    end

    scope
  end

  def write_sse_event(event)
    formatted = SpectatorEventFormatter.format(event)
    response.stream.write("id: #{event.id}\n")
    response.stream.write("event: #{event.event_type}\n")
    response.stream.write("data: #{formatted.to_json}\n\n")
  end
end
