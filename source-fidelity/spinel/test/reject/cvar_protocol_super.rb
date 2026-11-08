# A class/module object has Module's primitive, so this is a subset refusal,
# not Ruby's NoMethodError claiming there is no superclass implementation.
# spinel: reject-builtin-class: StorageProtocol.class_variable_set: super to an inherited builtin singleton method is not supported
module StorageProtocol
  def self.class_variable_set(name, value)
    super
  end
end
StorageProtocol.class_variable_set("@@value", 1)
