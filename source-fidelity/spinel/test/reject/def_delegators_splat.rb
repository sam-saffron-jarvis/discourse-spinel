# A def_delegators the parser cannot rewrite (a splatted name list) is
# refused where it is written; it defined nothing before (#4822).
require "forwardable"
class Inner
  def a = 1
end
NAMES = [:a]
class O
  extend Forwardable
  def_delegators :@inner, *NAMES
  def initialize = @inner = Inner.new
end
p O.new.a
