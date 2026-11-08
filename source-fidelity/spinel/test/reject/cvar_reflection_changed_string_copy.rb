# A copied String's bytes are not proved when String#+@ is user-defined.
# spinel: reject-builtin-class: unsupported call:
class String
  def +@ = "@@other"
end
module ChangedCvarNameCopy
  class_variable_set(+"@@value", 17)
  p class_variable_defined?("@@other")
end
