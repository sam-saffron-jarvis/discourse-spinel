# frozen_string_literal: true
# Shared live requires_login DSL storage. Arguments belong to the named
# class itself, not its parent, exactly as the original class-instance ivar.
class PortableControllerLoginPolicy
  @arguments = {}
  def self.set(name, argument)
    raise ArgumentError, "unsupported anonymous controller login policy" if name.nil? || name.empty?
    @arguments[name] = argument
  end
  def self.get(name)
    raise ArgumentError, "unsupported anonymous controller login policy" if name.nil? || name.empty?
    @arguments[name]
  end
end
