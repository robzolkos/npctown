class Agent < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "agt"

  API_KEY_PREFIX = "npc_"
  API_KEY_LENGTH = 40

  STATUSES = %w[active idle offline].freeze

  DEFAULTS = {
    stamina: 100,
    food: 50,
    energy: 100,
    currency: 100
  }.freeze

  belongs_to :location, optional: true
  has_many :events, dependent: :nullify
  has_many :memories, dependent: :destroy
  has_many :relationships, dependent: :destroy
  has_many :inverse_relationships, class_name: "Relationship",
           foreign_key: :target_agent_id, dependent: :destroy, inverse_of: :target_agent
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants
  has_many :conversation_messages, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :api_key_digest, presence: true, uniqueness: true
  validates :stamina, numericality: { in: 0..100 }
  validates :food, numericality: { greater_than_or_equal_to: 0 }
  validates :energy, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_personality_traits_limit
  validate :validate_goals_limit

  scope :active, -> { where(status: "active") }
  scope :at_location, ->(location) { where(location: location) }
  scope :online, -> { where(status: %w[active idle]) }

  # Generate a new agent with API key. Returns { agent:, api_key: }
  def self.create_with_api_key(attributes)
    raw_key = generate_api_key
    agent = new(
      **attributes,
      api_key_digest: digest_api_key(raw_key)
    )

    if agent.save
      { agent: agent, api_key: raw_key }
    else
      { agent: agent, api_key: nil }
    end
  end

  # Authenticate by raw API key
  def self.authenticate(raw_key)
    return nil unless raw_key.present? && raw_key.start_with?(API_KEY_PREFIX)

    digest = digest_api_key(raw_key)
    find_by(api_key_digest: digest)
  end

  def self.generate_api_key
    "#{API_KEY_PREFIX}#{SecureRandom.alphanumeric(API_KEY_LENGTH)}"
  end

  def self.digest_api_key(key)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, key)
  end

  private

  def validate_personality_traits_limit
    if personality_traits.is_a?(Array) && personality_traits.length > 5
      errors.add(:personality_traits, "cannot have more than 5 traits")
    end
  end

  def validate_goals_limit
    if goals.is_a?(Array) && goals.length > 3
      errors.add(:goals, "cannot have more than 3 goals")
    end
  end
end
