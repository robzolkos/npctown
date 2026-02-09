require "test_helper"

class OwnerTest < ActiveSupport::TestCase
  test "create_with_api_key returns owner and key" do
    result = Owner.create_with_api_key(
      email: "new@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    assert result[:owner].persisted?
    assert result[:api_key].start_with?("own_")
    assert_equal 44, result[:api_key].length
  end

  test "authenticate finds owner by raw key" do
    result = Owner.create_with_api_key(
      email: "auth@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    found = Owner.authenticate(result[:api_key])
    assert_equal result[:owner], found
  end

  test "authenticate returns nil for invalid key" do
    assert_nil Owner.authenticate("own_invalidkey12345678901234567890123456789")
    assert_nil Owner.authenticate(nil)
    assert_nil Owner.authenticate("")
    assert_nil Owner.authenticate("wrong_prefix")
  end

  test "verified? returns true when verified_at is set" do
    assert owners(:verified_owner).verified?
  end

  test "verified? returns false when verified_at is nil" do
    assert_not owners(:unverified_owner).verified?
  end

  test "can_register_agent? returns true for verified owner under limit" do
    owner = owners(:verified_owner)
    assert owner.can_register_agent?
  end

  test "can_register_agent? returns false for unverified owner" do
    assert_not owners(:unverified_owner).can_register_agent?
  end

  test "can_register_agent? returns false when at agent limit" do
    owner = owners(:verified_owner)
    owner.update!(agent_limit: 0)
    assert_not owner.can_register_agent?
  end

  test "generated ID has own prefix" do
    result = Owner.create_with_api_key(
      email: "prefix@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    assert result[:owner].id.start_with?("own_")
  end

  test "validates email presence" do
    result = Owner.create_with_api_key(
      email: "",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not result[:owner].persisted?
    assert result[:owner].errors[:email].any?
  end

  test "validates email uniqueness" do
    Owner.create_with_api_key(
      email: "dupe@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    result = Owner.create_with_api_key(
      email: "dupe@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not result[:owner].persisted?
    assert_includes result[:owner].errors[:email], "has already been taken"
  end

  test "validates email format" do
    result = Owner.create_with_api_key(
      email: "not-an-email",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not result[:owner].persisted?
    assert result[:owner].errors[:email].any?
  end

  test "has_secure_password validates password" do
    result = Owner.create_with_api_key(
      email: "pass@example.com",
      password: "",
      password_confirmation: ""
    )
    assert_not result[:owner].persisted?
  end
end
