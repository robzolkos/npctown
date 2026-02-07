class Conversation < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "conv"

  STATUSES = %w[active ended].freeze

  belongs_to :location
  has_many :conversation_participants, dependent: :destroy
  has_many :agents, through: :conversation_participants
  has_many :conversation_messages, dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at_tick, presence: true

  scope :active, -> { where(status: "active") }
  scope :at_location, ->(location) { where(location: location) }
end
