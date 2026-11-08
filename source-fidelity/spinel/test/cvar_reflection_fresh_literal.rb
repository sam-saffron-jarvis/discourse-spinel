# Literal fresh String names keep ordinary storage/query semantics. The
# String copy's bytes are proven; an overriding storage method still receives
# the actual mutable String argument, not a rewritten Symbol/frozen literal.
module FreshCvarNames
  class_variable_set(+"@@flag", nil)
  class_variable_set(+"@@tag", nil)
  def self.flag = @@flag
  def self.tag = @@tag
  p class_variable_defined?(+"@@flag"), class_variable_get(+"@@flag")
  p flag.nil?, tag.nil?
  @@flag = false
  @@tag = :ready
  p flag, tag
end
module FreshCvarOverride
  EVENTS = []
  def self.class_variable_set(name, value)
    EVENTS << name.is_a?(String).to_s
    EVENTS << name.frozen?.to_s
    name << "_seen"
    @@stored = value
  end
  class_variable_set(+"@@stored", 23)
  p EVENTS
  p @@stored
end
