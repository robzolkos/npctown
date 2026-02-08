class PagesController < ApplicationController
  def home
    render inertia: "Home"
  end

  def feed
    locations = Location.includes(agents: [ :plans, :relationships ]).order(:name).map do |loc|
      {
        id: loc.id,
        name: loc.name,
        type: loc.location_type,
        agents: loc.agents.active.order(:name).map { |a| serialize_agent(a) }
      }
    end

    render inertia: "Feed", props: {
      locations: locations,
      currentTick: Event.maximum(:tick) || 0
    }
  end

  def docs
    render inertia: "Docs"
  end

  private

  def serialize_agent(agent)
    {
      id: agent.id,
      name: agent.name,
      description: agent.description,
      personality_traits: agent.personality_traits || [],
      goals: agent.goals || [],
      stamina: agent.stamina,
      energy: agent.energy,
      food: agent.food,
      currency: agent.currency,
      status: agent.status,
      current_plan: agent.active_plan&.then { |p| { goal: p.goal, steps: p.steps, status: p.status } },
      relationships: agent.relationships.includes(:target_agent).map { |r|
        {
          target_id: r.target_agent_id,
          target_name: r.target_agent.name,
          trust: r.trust,
          affection: r.affection,
          respect: r.respect,
          familiarity: r.familiarity,
          label: r.label
        }
      }
    }
  end
end
