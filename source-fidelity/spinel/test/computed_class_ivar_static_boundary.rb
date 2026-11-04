# spinel: not-cruby -- the computed Class map must not shadow a typed static slot.
class StaticClassIvarBoundary
  @fixed = 17
  def self.fixed = @fixed
end
name = "@" + "fixed"
begin
  StaticClassIvarBoundary.instance_variable_set(name, false)
  raise "static slot overwritten"
rescue NotImplementedError
  puts "static Class slot refused"
end
p StaticClassIvarBoundary.fixed
unicode = "@" + "é"
begin
  StaticClassIvarBoundary.instance_variable_set(unicode, 1)
  raise "Unicode boundary bypassed"
rescue NotImplementedError
  puts "encoding boundary refused"
end
