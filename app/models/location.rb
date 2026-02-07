class Location < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "loc"

  TYPES = %w[social commerce knowledge].freeze

  has_many :agents, dependent: :nullify
  has_many :events, dependent: :nullify
  has_many :conversations, dependent: :destroy
  has_many :memories, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :location_type, presence: true, inclusion: { in: TYPES }

  scope :by_type, ->(type) { where(location_type: type) }
end
