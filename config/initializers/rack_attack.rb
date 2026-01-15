# Rate limiting configuration using rack-attack
# See https://github.com/rack/rack-attack for documentation

class Rack::Attack
  # Configure cache store for throttling
  # Use the same cache store as the Rails application
  self.cache.store = Rails.cache

  # Enable logging of blocked/throttled requests
  ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
    req = payload[:request]
    case req.env["rack.attack.match_type"]
    when :throttle
      Rails.logger.warn("[Rack::Attack] Throttled #{req.env['rack.attack.matched']} from #{req.ip} - #{req.path}")
    when :blocklist
      Rails.logger.warn("[Rack::Attack] Blocklisted #{req.ip} - #{req.path}")
    when :track
      Rails.logger.info("[Rack::Attack] Tracked #{req.ip} - #{req.path}")
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    period = match_data[:period]
    retry_after = (now + (period - now % period)).to_i

    headers = {
      "Content-Type" => "text/plain",
      "Retry-After" => retry_after.to_s,
      "RateLimit-Limit" => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset" => retry_after.to_s
    }

    [
      429, # status
      headers,
      [ "Rate limit exceeded. Please try again later.\n" ]
    ]
  end

  # Rate limit for auth callback endpoint: 5 requests per IP per minute
  # This is critical as it creates users in the database - very strict limit
  # Prevents resource exhaustion and arbitrary user creation attacks
  throttle("auth/callback by IP", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/auth/callback" && req.get?
  end

  # Rate limit for auth sign up endpoint: 5 requests per IP per minute
  # Very strict limit to prevent arbitrary user creation attempts
  # Each sign_up can result in a callback that creates a user in the database
  throttle("auth/sign_up by IP", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/auth/sign_up" && req.get?
  end

  # Additional protection: limit sign up attempts per IP per hour
  # Prevents distributed attempts to create many users over time
  throttle("auth/sign_up hourly by IP", limit: 20, period: 1.hour) do |req|
    req.ip if req.path == "/auth/sign_up" && req.get?
  end

  # Rate limit for auth sign in endpoint: 20 requests per IP per minute
  # Prevents abuse of CSRF token generation and Cognito redirects
  throttle("auth/sign_in by IP", limit: 20, period: 1.minute) do |req|
    req.ip if req.path == "/auth/sign_in" && req.get?
  end

  # Note: sign_out endpoint doesn't need specific rate limiting because:
  # - It's a very light operation (just clears session)
  # - No external API calls involved
  # - Protected by the generic rate limit rule if needed

  # Additional protection: limit callback attempts per IP per hour
  # Prevents distributed attempts to create many users via callbacks over time
  throttle("auth/callback hourly by IP", limit: 30, period: 1.hour) do |req|
    req.ip if req.path == "/auth/callback" && req.get?
  end

  # Additional protection: limit excessive repeated violations on auth endpoints
  # 50 requests per IP per 10 minutes for any auth endpoint
  throttle("auth endpoints repeated violations by IP", limit: 50, period: 10.minutes) do |req|
    if req.path.start_with?("/auth/") && (req.get? || %w[DELETE POST].include?(req.request_method))
      req.ip
    end
  end

  # Generic rate limit for all other endpoints (more permissive)
  # Excludes health checks, static assets, and already protected auth endpoints
  # This prevents general DoS attacks while allowing normal usage
  throttle("general requests by IP", limit: 300, period: 1.minute) do |req|
    # Skip health check endpoint (used by load balancers)
    next if req.path == "/up"

    # Skip static assets (handled by web server/CDN in production)
    next if req.path.start_with?("/assets/")
    next if req.path.start_with?("/packs/")

    # Skip already protected auth endpoints (they have specific rules)
    next if req.path.start_with?("/auth/")

    # Apply to all other endpoints
    req.ip
  end
end
