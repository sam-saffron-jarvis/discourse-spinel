# Forwardable's def_delegator with a setter alias (#4518). The textual
# rewrite made every delegation an endless def, and the grammar forbids an
# endless setter definition; a setter is now a one-line classic def whose
# body is the assignment.
require "forwardable"

class Timer
  attr_accessor :counter
end

class CIA
  extend Forwardable

  def initialize = @ta = Timer.new

  def_delegator :@ta, :counter,  :timer_a
  def_delegator :@ta, :counter=, :timer_a=
  def_delegators :@ta, :counter, :counter=
end

cia = CIA.new
cia.timer_a = 5
p cia.timer_a
cia.counter = 7
p cia.counter
p cia.timer_a
