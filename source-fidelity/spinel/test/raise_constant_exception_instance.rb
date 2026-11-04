# `raise ERR` where the constant holds an exception INSTANCE raised a class
# called "ERR": the one-argument constant arm of the raise emitter took every
# constant for a class name. The object path answers the instance itself.
ERR = RuntimeError.new("kept")
begin
  raise ERR
rescue => e
  p [e.class.name, e.message, e.equal?(ERR)]
end
err2 = RuntimeError.new("kept2")
begin
  raise err2
rescue => e
  p [e.class.name, e.message, e.equal?(err2)]
end
