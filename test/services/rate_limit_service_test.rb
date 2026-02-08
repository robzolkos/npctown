require "test_helper"

class RateLimitServiceTest < ActiveSupport::TestCase
  setup do
    @key = "test:#{Process.pid}:#{SecureRandom.hex(4)}"
    Sidekiq.redis { |c| c.del("npctown:ratelimit:#{@key}") }
  end

  teardown do
    Sidekiq.redis { |c| c.del("npctown:ratelimit:#{@key}") }
  end

  test "allows requests within limit" do
    assert_nothing_raised do
      3.times { RateLimitService.check!(@key, limit: 3, window: 60) }
    end
  end

  test "raises when limit exceeded" do
    3.times { RateLimitService.check!(@key, limit: 3, window: 60) }

    assert_raises(RateLimitService::RateLimitExceeded) do
      RateLimitService.check!(@key, limit: 3, window: 60)
    end
  end

  test "retry_after is a positive integer" do
    3.times { RateLimitService.check!(@key, limit: 3, window: 60) }

    error = assert_raises(RateLimitService::RateLimitExceeded) do
      RateLimitService.check!(@key, limit: 3, window: 60)
    end
    assert_kind_of Integer, error.retry_after
    assert error.retry_after >= 1
  end
end
