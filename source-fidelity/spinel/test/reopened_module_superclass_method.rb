# A module reopened to include its leaf modules, then included by a class
# whose superclass defines the method the leaf methods call (#4517). The
# transplant copied the outer module's method list as it stood when the class
# body was walked, before the reopening added the leaves, so the class could
# not reach them. Include bodies are processed in dependency order now: a
# module before the classes that include it, every reopening included.
class Cycleable
  def cycle
    result = yield if block_given?
    result
  end
end

module InstructionSet
  module Branch
    def bcc(addr) = branch(addr)
    def bcs(addr) = branch(addr)

    def branch(addr)
      cycle { @pc = addr }
    end
  end
end

module InstructionSet
  include InstructionSet::Branch

  def nop = cycle
end

class CPU < Cycleable
  include InstructionSet

  def go
    bcc(20)
    bcs(5)
    nop
  end
end

CPU.new.go
puts "ok"

module Badline
  module InstructionSet
    module Branch
      def bcc(addr) = branch(addr)
      def bcs(addr) = branch(addr)
      def branch(addr)
        cycle { @pc = addr }
      end
    end
  end
end

module Badline
  module InstructionSet
    module Flag
      def sei = cycle { @i = 1 }
      def cli = cycle { @i = 0 }
    end
  end
end

module Badline
  module InstructionSet
    include InstructionSet::Branch
    include Flag
    def nop = cycle
  end
end

module Badline
  class Cycleable
    def initialize = @pc = 0
    def cycle
      result = yield if block_given?
      result
    end
    def pc = @pc
  end

  class CPU < Cycleable
    include InstructionSet
    def go
      bcc(20)
      p pc
      bcs(5)
      p pc
      sei
      p @i
      cli
      p @i
      nop
    end
  end
end

Badline::CPU.new.go
puts "ok"
