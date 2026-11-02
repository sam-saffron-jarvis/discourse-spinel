# frozen_string_literal: true
# Source-only Emoji.normalize_name/[]/resolve_alias/load_standard adaptation.
# No unicode-rendering heuristic: existence includes aliases and toned aliases.
require "json"

module NativeEmoji
  CATALOG = JSON.parse(File.read(File.join(__dir__, "../data/emoji-existence.json"))).freeze

  # Source's deferred cache keys omit tone, so a non-tonable toned name can
  # appear to exist after an untoned lookup. Do not silently choose one result
  # for that cache-history-dependent stored value in the native serializer.
  def self.reaction_exists?(value)
    found = exists?(value)
    if !found && value.match?(/:t[1-6]:?\z/)
      base = value.sub(/:t[1-6](:?)\z/) { Regexp.last_match(1).to_s }
      raise "unsupported cache-sensitive emoji tone" if exists?(base)
    end
    found
  end

  def self.exists?(value)
    # Match the original normalization (including its refusal of malformed/nil
    # stored values), rather than silently inventing a valid reaction identity.
    raise "invalid stored emoji reaction value" unless value.is_a?(String)
    match = value.match(/\A:?(.+?)(?::t([1-6]))?:?\z/)
    raise "invalid stored emoji reaction value" unless match
    name = match[1].to_s
    toned = !match[2].nil?
    standard = CATALOG.fetch("standard")
    return true if standard.key?(name) && (!toned || standard[name] == true)
    original = CATALOG.fetch("aliases")[name]
    !original.nil? && standard.key?(original) && (!toned || standard[original] == true)
  end
end
