class ComputedClassIvarSourceOverride
  def self.instance_variable_get(name) = 31
  def self.instance_variable_set(name, value) = value + 1
end
name = "@" + "original"
p ComputedClassIvarSourceOverride.instance_variable_get(name)
p ComputedClassIvarSourceOverride.instance_variable_set(name, 17)
