# Literal reflective self-calls participate in inherited class-method
# specialization before public_send is desugared. Each class owns its @cache.
class ReflectiveReader
  def self.raw
    @cache || (@cache = [-1, 2, 3])
  end
  def self.items
    public_send(:raw).select { |value| value > 0 }
  end
  def self.explicit_items
    self.public_send("raw").select { |value| value > 0 }
  end
end
class ChildReflectiveReader < ReflectiveReader; end
ReflectiveReader.raw << 4
ChildReflectiveReader.raw << 5
p [ReflectiveReader.items, ChildReflectiveReader.items]
p [ReflectiveReader.explicit_items, ChildReflectiveReader.explicit_items]

# The source reader may be an alias of an earlier method version.
class AliasReflectiveReader
  def self.items
    @cache || (@cache = [1])
  end
  class << self
    alias_method :raw, :items
  end
  def self.items
    public_send(:raw).select { |value| value > 0 }
  end
end
class ChildAliasReflectiveReader < AliasReflectiveReader; end
AliasReflectiveReader.raw << 2
ChildAliasReflectiveReader.raw << 3
p [AliasReflectiveReader.items, ChildAliasReflectiveReader.items]

# An app's own public_send is not the builtin reflective call. Its own
# stateful implementation, not the unused literal target, needs specialization.
class CustomReflectiveReader
  def self.public_send(name)
    @calls || (@calls = [])
    @calls << name
    @calls
  end
  def self.target
    :unused
  end
  def self.call
    public_send(:target)
  end
end
class ChildCustomReflectiveReader < CustomReflectiveReader; end
p CustomReflectiveReader.call
p ChildCustomReflectiveReader.call
p CustomReflectiveReader.call
