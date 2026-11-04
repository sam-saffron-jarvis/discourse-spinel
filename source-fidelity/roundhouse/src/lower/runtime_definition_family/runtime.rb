# frozen_string_literal: true

# Concrete runtime template for one zero-argument definition family.
# The lowerer substitutes every __PLACEHOLDER__ before this source is
# parsed or emitted. The body receives its receiver explicitly: calling a
# stored closure never attempts to rebind Proc#self.
module __REGISTRY__
  class __ENTRY__
    def initialize(token, original_name, body)
      @token = token
      @original_name = original_name
      @body = body
      freeze
    end

    def token
      @token
    end

    def original_name
      @original_name
    end

    def body
      @body
    end
  end

  class __SLOT__
    def initialize(entry, visibility)
      @entry = entry
      @visibility = visibility
      freeze
    end

    def entry
      @entry
    end

    def visibility
      @visibility
    end
  end

  class __BOUND__
    def initialize(receiver, name, entry)
      @receiver = receiver
      @name = name
      @entry = entry
      freeze
    end

    def call
      @entry.body.call(@receiver, @name, @entry.original_name)
    end

    def name
      @name
    end

    def original_name
      @entry.original_name
    end

    def receiver
      @receiver
    end

    def entry
      @entry
    end

    def arity
      0
    end

    def ==(other)
      @receiver.equal?(other.receiver) && @entry.token == other.entry.token
    end
  end

  class __STATE__
    def initialize
      @entries = {}
      @next_token = 0
      @extensions = {}
    end

    def entries
      @entries
    end

    def extensions
      @extensions
    end

    def next_token
      @next_token
    end

    def next_token=(value)
      @next_token = value
    end
  end

  __STATE_VALUE__ = __STATE__.new

  def self.empty_slots
    {}
  end

  def self.activate_extension(owner)
    __STATE_VALUE__.extensions[owner] = true
    nil
  end

  def self.extension_active(receiver)
    current = receiver
    while !current.nil?
      return true if __STATE_VALUE__.extensions[current]
      current = parent_of(current)
    end
    false
  end

  def self.require_extension(receiver)
    unless extension_active(receiver)
      raise NoMethodError.new("extension method called before its source extend event")
    end
    nil
  end

  def self.extension_api_name(name)
    __EXTENSION_API_DISPATCH__
  end

  def self.ensure_virtual_name(owner, name)
    if owner.respond_to?(name, true)
      raise NotImplementedError.new("replacing a native method is outside this runtime definition family")
    end
    nil
  end

  def self.install(owner, name, body, callback)
    ensure_virtual_name(owner, name)
    token = __STATE_VALUE__.next_token
    __STATE_VALUE__.next_token = __STATE_VALUE__.next_token + 1
    entry = __ENTRY__.new(token, name, body)
    slot = __SLOT__.new(entry, 0)
    owner_entries = __STATE_VALUE__.entries[owner]
    if owner_entries.nil?
      owner_entries = empty_slots
      __STATE_VALUE__.entries[owner] = owner_entries
    end
    owner_entries[name] = slot
    callback.call(owner, name)
    name
  end

  def self.parent_of(receiver)
    __PARENT_DISPATCH__
  end

  def self.lookup(receiver, name, inherit)
    current = receiver
    while !current.nil?
      owner_entries = __STATE_VALUE__.entries[current]
      unless owner_entries.nil?
        slot = owner_entries[name]
        return slot unless slot.nil?
      end
      return nil unless inherit
      return nil if current == __OWNER__
      current = parent_of(current)
    end
    nil
  end

  def self.alias_name(owner, to, from, callback)
    ensure_virtual_name(owner, to)
    source = lookup(owner, from, true)
    raise NameError.new("undefined method `#{from}' for #{owner}") if source.nil?

    owner_entries = __STATE_VALUE__.entries[owner]
    if owner_entries.nil?
      owner_entries = empty_slots
      __STATE_VALUE__.entries[owner] = owner_entries
    end
    owner_entries[to] = __SLOT__.new(source.entry, source.visibility)
    callback.call(owner, to)
    to
  end

  def self.set_visibility(owner, name, visibility)
    source = lookup(owner, name, true)
    raise NameError.new("undefined method `#{name}' for #{owner}") if source.nil?

    owner_entries = __STATE_VALUE__.entries[owner]
    if owner_entries.nil?
      owner_entries = empty_slots
      __STATE_VALUE__.entries[owner] = owner_entries
    end
    owner_entries[name] = __SLOT__.new(source.entry, visibility)
    owner
  end

  def self.present(receiver, name, include_private)
    slot = lookup(receiver, name, true)
    return false if slot.nil?
    include_private || slot.visibility == 0
  end

  def self.responds(receiver, name, include_private)
    return false if extension_api_name(name) && !extension_active(receiver)
    present(receiver, name, include_private) || receiver.respond_to?(name, include_private)
  end

  def self.call(receiver, name, allow_private)
    slot = lookup(receiver, name, true)
    ensure_virtual_name(receiver, name) if slot.nil?
    if slot.nil? || (!allow_private && slot.visibility != 0)
      raise NoMethodError.new("undefined method `#{name}' for #{receiver}")
    end
    __BOUND__.new(receiver, name, slot.entry).call
  end

  def self.bind(receiver, name, public_only)
    slot = lookup(receiver, name, true)
    ensure_virtual_name(receiver, name) if slot.nil?
    if slot.nil? || (public_only && slot.visibility != 0)
      raise NameError.new("undefined method `#{name}' for #{receiver}")
    end
    __BOUND__.new(receiver, name, slot.entry)
  end
end
