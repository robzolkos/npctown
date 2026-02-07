class PagesController < ApplicationController
  def home
    render inertia: "Home", props: {
      location_count: Location.count,
      agent_count: Agent.count
    }
  end
end
