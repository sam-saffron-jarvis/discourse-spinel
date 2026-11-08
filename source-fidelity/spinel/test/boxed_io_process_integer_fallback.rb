# Integer IO/process accessors must box into widened dynamic result slots.
# No child process or network connection is created by this regression.
require "ostruct"
class OtherIntegerAccessors
  def pid = {kind: "user-pid"}
  def fileno = {kind: "user-fd"}
end

def pid_of(value)
  value.pid
end

def fileno_of(value)
  value.fileno
end

class CurrentProcessId
  def pid = Process.pid
end

p pid_of(CurrentProcessId.new) == Process.pid
begin
  pid_of(Thread.current)
rescue NoMethodError
  puts "no-thread-pid"
end
p pid_of(OtherIntegerAccessors.new)
p pid_of(OpenStruct.new(pid: "dynamic-pid"))
File.open(__FILE__) do |file|
  number = fileno_of(file)
  p number.is_a?(Integer) && number >= 0
end
p fileno_of(OtherIntegerAccessors.new)
p fileno_of(OpenStruct.new(fileno: "dynamic-fd"))
