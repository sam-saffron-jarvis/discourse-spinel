# Shared caller, never loaded by a production request.
def state(label)
  puts "#{label}:#{Current.value.inspect}:#{OtherCurrent.value.inspect}:#{ActiveSupport::ExecutionContext.current_attributes_instances.size}:#{ActiveSupport::ExecutionContext.to_h.inspect}"
end
ActiveSupport::ExecutionContext.nestable = true
Current.value = "outer"
OtherCurrent.value = "other-outer"
outer = Current.instance
ActiveSupport::ExecutionContext[:request] = "outer"
state("outer")
ActiveSupport::ExecutionContext.push
raise "frame reused outer instance" if Current.instance.equal?(outer)
state("inner-empty")
Current.value = "inner"
OtherCurrent.value = "other-inner"
inner = Current.instance
other_inner = OtherCurrent.instance
ActiveSupport::ExecutionContext[:request] = "inner"
state("inner")
Current.reset
OtherCurrent.reset
raise "reset replaced instance" unless Current.instance.equal?(inner)
raise "second class not reset" unless other_inner.value.nil?
state("reset-retains-registry")
Current.value = "before-close"
OtherCurrent.value = "other-before-close"
ActiveSupport::CurrentAttributes.clear_all
raise "held inner reference not reset" unless inner.value.nil?
raise "other registered instance not reset" unless other_inner.value.nil?
puts "clear-all:#{ActiveSupport::ExecutionContext.current_attributes_instances.empty?}"
ActiveSupport::ExecutionContext.pop
raise "outer instance lost" unless Current.instance.equal?(outer)
state("outer-restored")
ActiveSupport::ExecutionContext.push
Current.value = "flush-inner"
ActiveSupport::ExecutionContext.flush
ActiveSupport::ExecutionContext.pop
state("flush-empties-outer")
ActiveSupport::ExecutionContext.nestable = false
Current.value = "non-nestable"
ActiveSupport::ExecutionContext.push
state("non-nestable-push-clears")
Current.value = "request"
held = Current.instance
ActiveSupport::CurrentAttributes.clear_all
ActiveSupport::ExecutionContext.pop
raise "completion did not reset actual instance" unless held.value.nil?
state("non-nestable-pop-clears")
# Each thread owns its own registry, independent of the caller's frame.
Current.value = "main"
thread = Thread.new do
  raise "thread inherited registry" unless Current.value.nil?
  Current.value = "worker"
  ActiveSupport::CurrentAttributes.clear_all
end
thread.join
state("thread-isolated")
ActiveSupport::CurrentAttributes.clear_all
ActiveSupport::ExecutionContext.clear
