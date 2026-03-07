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

  # Rodauth owns authentication flow control. Keep Rack::Attack focused on
  # signup flooding and generic request abuse, instead of duplicating auth logic.
  throttle("auth sign-up by IP", limit: 10, period: 10.minutes) do |req|
    if req.path == "/auth/sign_up" && %w[GET POST].include?(req.request_method)
      req.ip
    end
  end

  # Generic rate limit for all other endpoints (more permissive).
  # Excludes health checks, static assets, and Rodauth routes with dedicated rules.
  throttle("general requests by IP", limit: 300, period: 1.minute) do |req|
    next if req.path == "/up"
    next if req.path.start_with?("/assets/")
    next if req.path.start_with?("/packs/")
    next if req.path.start_with?("/auth/")
    req.ip
  end
end
