# A writer declaration/metadata slot does not assign storage. The actual
# overridable protocol can decline the write; readers must still raise.
module NonWritingCvarProtocol
  def self.class_variable_set(name, value) = value
  class_variable_set("@@value", nil) unless class_variable_defined?("@@value")
  def self.value = @@value
  def self.value=(value); @@value = value; end
  p class_variable_defined?("@@value")
  begin
    value
  rescue NameError => error
    puts error.message
  end
  self.value = 29
  p value
end
