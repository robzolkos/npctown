class RateLimitService
  class RateLimitExceeded < StandardError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super("Rate limit exceeded. Retry after #{retry_after} seconds.")
    end
  end

  def self.check!(key, limit:, window:)
    full_key = "npctown:ratelimit:#{key}"

    count = Sidekiq.redis do |conn|
      conn.multi do |m|
        m.incr(full_key)
        m.expire(full_key, window)
      end.first
    end

    if count > limit
      ttl = Sidekiq.redis { |c| c.ttl(full_key) }
      retry_after = [ ttl, 1 ].max
      raise RateLimitExceeded.new(retry_after)
    end

    true
  end
end
