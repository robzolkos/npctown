class Memory < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "mem"

  TYPES = %w[observation reflection plan].freeze

  belongs_to :agent
  belongs_to :location, optional: true

  validates :memory_type, presence: true, inclusion: { in: TYPES }
  validates :content, presence: true
  validates :importance, presence: true, numericality: { in: 1..10 }
  validates :tick, presence: true

  scope :observations, -> { where(memory_type: "observation") }
  scope :reflection_type, -> { where(memory_type: "reflection") }
  scope :plans, -> { where(memory_type: "plan") }
  scope :by_importance, -> { order(importance: :desc) }
  scope :recent, -> { order(tick: :desc) }
  scope :about_agent, ->(agent_id) { where("related_agent_ids @> ?", [ agent_id ].to_json) }
end
