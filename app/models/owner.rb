class Owner < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "own"

  API_KEY_PREFIX = "own_"
  API_KEY_LENGTH = 40

  has_secure_password

  has_many :agents, dependent: :nullify
  has_many :gate_applications, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :api_key_digest, presence: true, uniqueness: true

  # Generate a new owner with API key. Returns { owner:, api_key: }
  def self.create_with_api_key(attributes)
    raw_key = generate_api_key
    owner = new(
      **attributes,
      api_key_digest: digest_api_key(raw_key)
    )

    if owner.save
      { owner: owner, api_key: raw_key }
    else
      { owner: owner, api_key: nil }
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

  def verified?
    verified_at.present?
  end

  def can_register_agent?
    verified? && agents.count < agent_limit
  end
end
