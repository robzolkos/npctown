class Event < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "evt"

  TYPES = %w[
    agent_registered
    agent_moved
    agent_spoke
    agent_action
    tick_advanced
    conversation_started
    conversation_message
    conversation_ended
    memory_created
    reflection_created
    relationship_changed
    resource_changed
    stamina_changed
  ].freeze

  belongs_to :agent, optional: true
  belongs_to :location, optional: true

  validates :event_type, presence: true, inclusion: { in: TYPES }
  validates :tick, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :of_type, ->(type) { where(event_type: type) }
  scope :since_tick, ->(tick) { where("tick >= ?", tick) }
  scope :at_location, ->(location) { where(location: location) }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :recent, -> { order(tick: :desc, created_at: :desc) }
  scope :chronological, -> { order(tick: :asc, created_at: :asc) }
end
