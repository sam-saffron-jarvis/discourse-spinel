class NativeComputedClassCache
  def self.write(key, value)
    self.instance_variable_set("@#{key}_cache", value)
  end
  def self.read(key)
    self.instance_variable_get("@#{key}_cache")
  end
end
class NativeComputedChildCache < NativeComputedClassCache
end
key = "dynamic" + "_field"
p NativeComputedClassCache.read(key)
p NativeComputedClassCache.write(key, false)
p NativeComputedClassCache.read(key)
p NativeComputedChildCache.read(key)
p NativeComputedChildCache.write(key, 29)
p NativeComputedChildCache.read(key)
p NativeComputedClassCache.read(key)
p NativeComputedClassCache.write(key, :missing)
p NativeComputedClassCache.read(key)
# Captured runtime Class receiver, not a root constant or instance self.
reader = ->(owner, name) { owner.instance_variable_get("@#{name}_cache") }
p reader.call(NativeComputedClassCache, key)
p reader.call(NativeComputedChildCache, key)
# A nil is really stored/unset, not confused with a cached false.
p NativeComputedClassCache.write(key, nil)
p NativeComputedClassCache.read(key)
