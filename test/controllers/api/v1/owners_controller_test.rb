require "test_helper"

class Api::V1::OwnersControllerTest < ActionDispatch::IntegrationTest
  # --- POST /api/v1/owners ---

  test "create registers owner and returns ownerId and apiKey" do
    assert_difference("Owner.count", 1) do
      post api_v1_owners_url, params: {
        email: "new@example.com",
        password: "password123",
        password_confirmation: "password123"
      }, as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert json["ownerId"].start_with?("own_")
    assert json["apiKey"].start_with?("own_")
  end

  test "create auto-verifies in non-production" do
    post api_v1_owners_url, params: {
      email: "dev@example.com",
      password: "password123",
      password_confirmation: "password123"
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["verified"]
  end

  test "create returns 422 with invalid email" do
    post api_v1_owners_url, params: {
      email: "not-an-email",
      password: "password123",
      password_confirmation: "password123"
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "Validation failed", json["error"]
  end

  test "create returns 422 with duplicate email" do
    post api_v1_owners_url, params: {
      email: owners(:verified_owner).email,
      password: "password123",
      password_confirmation: "password123"
    }, as: :json

    assert_response :unprocessable_entity
  end

  test "create returns 429 after exceeding rate limit" do
    # Use a unique IP so parallel test processes don't interfere
    unique_ip = "10.0.#{rand(256)}.#{rand(256)}"

    5.times do |i|
      post api_v1_owners_url,
        params: { email: "ratelimit#{i}@example.com", password: "password123", password_confirmation: "password123" },
        headers: { "REMOTE_ADDR" => unique_ip },
        as: :json
    end

    post api_v1_owners_url,
      params: { email: "ratelimit_over@example.com", password: "password123", password_confirmation: "password123" },
      headers: { "REMOTE_ADDR" => unique_ip },
      as: :json

    assert_response :too_many_requests
    assert response.headers["Retry-After"].present?
  end

  # --- POST /api/v1/owners/login ---

  test "login returns 200 with new apiKey" do
    result = Owner.create_with_api_key(
      email: "login@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    assert result[:owner].persisted?

    post login_api_v1_owners_url, params: {
      email: "login@example.com",
      password: "password123"
    }, as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["ownerId"].start_with?("own_")
    assert json["apiKey"].start_with?("own_")
  end

  test "login rotates the API key" do
    result = Owner.create_with_api_key(
      email: "rotate@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    old_digest = result[:owner].api_key_digest

    post login_api_v1_owners_url, params: {
      email: "rotate@example.com",
      password: "password123"
    }, as: :json

    assert_response :ok
    result[:owner].reload
    assert_not_equal old_digest, result[:owner].api_key_digest
  end

  test "login returns 401 with wrong password" do
    Owner.create_with_api_key(
      email: "wrongpw@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    post login_api_v1_owners_url, params: {
      email: "wrongpw@example.com",
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized
  end

  test "login returns 401 with unknown email" do
    post login_api_v1_owners_url, params: {
      email: "nobody@example.com",
      password: "password123"
    }, as: :json

    assert_response :unauthorized
  end

  test "login returns 429 after exceeding rate limit" do
    unique_ip = "10.1.#{rand(256)}.#{rand(256)}"

    10.times do
      post login_api_v1_owners_url,
        params: { email: "nobody@example.com", password: "wrong" },
        headers: { "REMOTE_ADDR" => unique_ip },
        as: :json
    end

    post login_api_v1_owners_url,
      params: { email: "nobody@example.com", password: "wrong" },
      headers: { "REMOTE_ADDR" => unique_ip },
      as: :json

    assert_response :too_many_requests
  end

  # --- POST /api/v1/owners/verify ---

  test "verify sets verified_at and returns verified true" do
    result = Owner.create_with_api_key(
      email: "toverify@example.com",
      password: "password123",
      password_confirmation: "password123",
      email_verification_token: "test_token_123"
    )
    # Clear auto-verification so we can test the verify endpoint
    result[:owner].update_columns(verified_at: nil)

    post verify_api_v1_owners_url, params: { token: "test_token_123" }, as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["verified"]

    result[:owner].reload
    assert result[:owner].verified?
    assert_nil result[:owner].email_verification_token
  end

  test "verify returns 404 with invalid token" do
    post verify_api_v1_owners_url, params: { token: "bogus_token" }, as: :json

    assert_response :not_found
  end
end
