# A captured earlier definition has its own function under the alias name.
# __method__ keeps the def name; __callee__ must not fall back to it when a
# direct singleton/instance call needs no called-name channel.
class CapturedCallee
  def self.value(arg = nil)
    [__method__, __callee__, arg]
  end
  class << self
    alias_method :raw, :value
  end
  def self.value(arg = nil)
    :replacement
  end
  def self.argument
    __callee__
  end

  def item
    [__method__, __callee__]
  end
  alias saved_item item
  def item
    :new_item
  end
end
class CapturedCalleeChild < CapturedCallee
end
p CapturedCallee.raw
p CapturedCallee.raw(CapturedCallee.argument)
p CapturedCallee.value
p CapturedCalleeChild.raw
p CapturedCallee.new.saved_item
p CapturedCallee.new.item
