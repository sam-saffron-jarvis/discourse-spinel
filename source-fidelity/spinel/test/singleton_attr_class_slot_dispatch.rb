# A class method called through a class object held in a `class << self;
# attr_reader` slot.
#
# The emitter resolves the slot statically -- one write, one constant -- and
# devirtualizes the call to that class's C function, with its concrete return
# (sp_int, const char *, sp_bool). The inference had the same fold, but it sat
# BELOW every rule that decides by the receiver's type, and the receiver -- a
# read of that slot -- types poly. So the site was typed poly, the emitter
# handed it a raw C scalar, and clang refused the seam (#4426).
#
# The hand-written reader never had the problem: `def self.adapter; @adapter;
# end` is a class method with a typed return, not a slot, so it took a
# different path. That is the asymmetry in the report's A/B table, and the
# fold now runs first for both.
module Sqlite
  def self.insert(table, attrs)
    attrs.size + 41
  end

  def self.label(table)
    "r" + table
  end

  def self.big?(attrs)
    attrs.size > 1
  end
end

module AR
  class << self
    attr_accessor :adapter
  end
end

module AR2
  class << self
    attr_reader :adapter
  end

  def self.adapter=(a)
    @adapter = a
  end
end

AR.adapter = Sqlite
AR2.adapter = Sqlite

# an Integer return, in an expression
puts AR.adapter.insert("blobs", { "name" => "x" }) + 1

# a String return
puts AR.adapter.label("t")

# a bool return
puts AR.adapter.big?({ "a" => 1, "b" => 2 })

# assigned to a local, and converted
n = AR.adapter.insert("blobs", { "name" => "x" })
puts n
puts AR.adapter.insert("blobs", {}).to_i

# attr_reader with an explicit writer is the same slot
puts AR2.adapter.insert("blobs", { "k" => "v" })
