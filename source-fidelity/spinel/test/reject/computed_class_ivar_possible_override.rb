class PlainClassIvarReceiver
end
class OwnClassIvarReceiver
  def self.instance_variable_get(name)
    31
  end
end
def read_unknown_class(owner, name)
  owner.instance_variable_get(name)
end
name = "@" + "field"
p read_unknown_class(PlainClassIvarReceiver, name)
p read_unknown_class(OwnClassIvarReceiver, name)
