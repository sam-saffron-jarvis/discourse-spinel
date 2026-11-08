# A built-in IO Boolean must be boxed in a widened user-method dispatch.
require "ostruct"
class OtherSyncResult
  def sync = {kind: "user"}
end

def sync_of(value)
  value.sync
end

File.open(__FILE__) do |file|
  file.sync = false
  p sync_of(file)
  file.sync = true
  p sync_of(file)
end
p sync_of(OtherSyncResult.new)
p sync_of(OpenStruct.new(sync: "dynamic"))
