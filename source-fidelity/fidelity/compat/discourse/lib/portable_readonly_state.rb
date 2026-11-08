# frozen_string_literal: true

# Shared readonly READ policy. Constants are supplied by the generated pinned
# Discourse declarations, not an effective mode snapshot. Distributed timestamp
# read-cache is deliberately replaced by a fresh real Redis read; no MessageBus
# publication/cache-effect equivalence is claimed by this single-site profile.
class PortableReadonlyState
  def self.readonly?(redis, force, redis_error_at, now)
    (redis_error_at && redis_error_at > now - 15) ||
      postgres_recently_readonly?(redis, now) || force || redis.exists?(*READONLY_KEYS)
  end

  def self.postgres_recently_readonly?(redis, now)
    seconds = redis.get(LAST_POSTGRES_READONLY_KEY)
    seconds ? Time.at(seconds.to_i) > now - 15 : false
  end

  def self.staff_writes_only?(redis)
    value = redis.get(STAFF_WRITES_ONLY_MODE_KEY)
    !value.nil? && !/\A[[:space:]]*\z/.match?(value)
  end
end

# Actual RESP connection adapter implementing DiscourseRedis's namespace_key,
# GET and EXISTS surface. Never an in-memory Redis substitute or connection
# factory: the already guarded/injected live connection owns all transport.
class PortableNamespacedRedis
  attr_reader :namespace

  def initialize(connection, namespace)
    raise ArgumentError, "empty application cache namespace" if namespace.empty?
    @connection = connection
    @namespace = namespace
  end

  def namespace_key(key)
    "#{@namespace}:#{key}"
  end

  def get(key)
    @connection.get(namespace_key(key))
  end

  def exists?(*keys)
    qualified = keys.map { |key| namespace_key(key) }
    @connection.call(["EXISTS", *qualified]).to_i > 0
  end
end

# Bootstrap context, not a mode value map. The force flag is re-read from real
# configuration; the local error time changes only through an actual report API.
class PortableReadonlyContext
  def self.configure(connection, configuration, namespace)
    @redis = PortableNamespacedRedis.new(connection, namespace)
    @configuration = configuration
    @redis_error_at = nil
  end

  def self.redis
    @redis || raise(ArgumentError, "application readonly cache is not configured")
  end

  def self.force?
    value = @configuration.value("pg_force_readonly_mode")
    unless value.nil? || value == true || value == false
      raise ArgumentError, "unsupported non-boolean pg_force_readonly_mode"
    end
    value == true
  end

  def self.redis_error_at
    @redis_error_at
  end

  def self.received_redis_readonly!
    @redis_error_at = Time.now
  end

  def self.clear_redis_readonly!
    @redis_error_at = nil
  end
end
