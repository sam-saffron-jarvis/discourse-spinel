# A program with a `gets` of its own keeps it: one reached through a
# top-level include, or a class's own `def self.gets` called from its body,
# answers a bare `gets`, rather than the line Kernel#gets would read from
# ARGF. 855c69a9 already answers these.
module FromInclude
  def gets = "include"
end
include FromInclude
p gets
p [1].map { gets }

class Config
  def self.gets = "class"
  VALUE = gets
end
p Config::VALUE
