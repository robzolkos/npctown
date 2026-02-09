class Api::V1::OwnersController < Api::V1::BaseController
  skip_before_action :authenticate_agent!
  wrap_parameters false

  # POST /api/v1/owners
  def create
    ip_rate_limit!("owner_register", limit: 5, window: 1.hour.to_i)

    token = SecureRandom.urlsafe_base64
    attrs = owner_params.to_h.merge(email_verification_token: token)
    attrs[:verified_at] = Time.current unless Rails.env.production?

    result = Owner.create_with_api_key(attrs)
    owner = result[:owner]

    if owner.persisted?
      render json: {
        ownerId: owner.id,
        apiKey: result[:api_key],
        verified: owner.verified?
      }, status: :created
    else
      render_error("Validation failed", :unprocessable_entity, errors: owner.errors.full_messages)
    end
  end

  # POST /api/v1/owners/login
  def login
    ip_rate_limit!("owner_login", limit: 10, window: 5.minutes.to_i)

    owner = Owner.find_by(email: params[:email])
    unless owner&.authenticate(params[:password])
      return render_error("Invalid email or password", :unauthorized)
    end

    new_key = Owner.generate_api_key
    owner.update!(api_key_digest: Owner.digest_api_key(new_key))

    render json: { ownerId: owner.id, apiKey: new_key }
  end

  # POST /api/v1/owners/verify
  def verify
    owner = Owner.find_by(email_verification_token: params[:token])
    return render_error("Invalid verification token", :not_found) unless owner

    owner.update!(verified_at: Time.current, email_verification_token: nil)

    render json: { verified: true }
  end

  private

  def owner_params
    params.permit(:email, :password, :password_confirmation)
  end
end
