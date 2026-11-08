# frozen_string_literal: true
# AMS0.8.4 read algorithm with source declarations statically expanded.
# Dynamic serializer mutation, scope aliases, cache activation and unknown
# serializer classes are NOT admitted by this explicit read profile.
class PortableSerializerRead
  attr_reader :object, :options
  def initialize(object, options = {})
    raise ArgumentError, "unsupported serializer scope alias" if options[:scope_name]
    raise ArgumentError, "unsupported authenticated serializer scope" if options[:scope] && options[:scope].user
    @object, @options = object, options
  end
  def self._root; nil; end
  def self._embed; :objects; end
  def self._root_embed; nil; end
  def self.cache; nil; end
  def self.perform_caching; nil; end
  def _root
    self.class._root
  end

def _embed
    self.class._embed
  end

def _root_embed
    self.class._root_embed
  end

def cache
    self.class.cache
  end

def perform_caching
    self.class.perform_caching
  end

  def root_name
      return false if self._root == false

      class_name = self.class.name.demodulize.underscore.sub(/_serializer$/, '').to_sym unless self.class.name.blank?

      if self._root == true
        class_name
      else
        self._root || class_name
      end
    end

def url_options
      @options[:url_options] || {}
    end

def meta_key
      @options[:meta_key].try(:to_sym) || :meta
    end

def include_meta(hash)
      hash[meta_key] = @options[:meta] if @options.has_key?(:meta)
    end

def as_json(options={})
      options ||= {}
      if root = options.fetch(:root, @options.fetch(:root, root_name))
        @options[:hash] = hash = {}
        @options[:unique_values] = {}

        hash.merge!(root => serializable_hash)
        include_meta hash
        hash
      else
        serializable_hash
      end
    end

def serializable_hash; raise ArgumentError, "unsupported activated serializer caching" if perform_caching?; @node = _serializable_hash; include_associations! if @object.present? && _embed; @node; end

def merge_association(hash, key, serializables, unique_values)
      already_serialized = (unique_values[key] ||= {})
      serializable_hashes = (hash[key] ||= [])

      serializables.each do |serializable|
        unless already_serialized.include? serializable.object
          already_serialized[serializable.object] = true
          serializable_hashes << serializable.serializable_hash
        end
      end
    end

def scope
      @options[:scope]
    end

def _serializable_hash
      return nil if @object.nil?
      attributes
    end

def perform_caching?
      perform_caching && cache && respond_to?(:cache_key)
    end
end
