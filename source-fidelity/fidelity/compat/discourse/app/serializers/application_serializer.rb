# frozen_string_literal: true

require "distributed_cache"

require_relative "../../lib/portable_serializer_read"

class ApplicationSerializer < PortableSerializerRead


  class CachedFragment
    def initialize(json)
      @json = json
    end

    def as_json(*_args)
      @json
    end
  end

  def self.expire_cache_fragment!(name_or_regexp)
    case name_or_regexp
    when String
      fragment_cache.delete(name_or_regexp)
    when Regexp
      fragment_cache.clear_regex(name_or_regexp)
    end
  end

  def self.fragment_cache
    @cache ||= DistributedCache.new("am_serializer_fragment_cache")
  end

  protected

  def cache_fragment(name, &block)
    ApplicationSerializer.fragment_cache.defer_get_set(name, &block)
  end

  def cache_anon_fragment(name, &blk)
    if scope.anonymous?
      cache_fragment(name, &blk)
    else
      blk.call
    end
  end

  public
  def self._embed; :ids; end

  def _embed; :ids; end

  def self._root_embed; true; end

  def _root_embed; true; end

  def attributes
    result = {}

    result
  end

  def include?(name)
  return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
  return false if @options.key?(:except) && Array(@options[:except]).include?(name)
  raise ArgumentError, "unknown serializer field"
end


  def include_associations!

    nil
  end
end
