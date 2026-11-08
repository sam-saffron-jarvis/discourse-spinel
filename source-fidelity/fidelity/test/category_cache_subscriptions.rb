# frozen_string_literal: true
# Typed representation of the single source subscription topology. In particular
# nil site keys are not coerced to Strings. Unknown topology fails closed.
class CategoryCacheChannelSubscriptions
  def initialize
    @callbacks = []
  end
  def register(channel, callback)
    raise ArgumentError, "category cache subscription channel" unless channel == "/distributed_hash"
    raise ArgumentError, "duplicate category cache subscription" unless @callbacks.empty?
    raise ArgumentError, "category cache subscription callback missing" unless callback.is_a?(Proc)
    @callbacks << callback
  end
  def [](channel)
    channel == "/distributed_hash" ? @callbacks : nil
  end
end
class CategoryCacheSubscriptions
  def initialize
    @global = CategoryCacheChannelSubscriptions.new
  end
  def register(channel, site, callback)
    raise ArgumentError, "category cache subscription site" unless site.nil?
    @global.register(channel, callback)
  end
  def [](site)
    site.nil? ? @global : nil
  end
end
