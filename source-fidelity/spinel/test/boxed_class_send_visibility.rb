# A Class held boxed must keep send/__send__ visibility bypass, while
# public_send and ordinary explicit receivers still reject private targets.
class BoxedClassVisibility
  def self.hidden(value)
    value
  end
  private_class_method :hidden
end
receiver = [BoxedClassVisibility, "not a class"][ARGV.length]
p receiver.send(:hidden, :send)
p receiver.__send__(:hidden, :__send__)
begin
  receiver.public_send(:hidden, :wrong)
  raise "public_send bypassed private class visibility"
rescue NoMethodError
  puts "public_send rejected"
end
begin
  receiver.hidden(:wrong)
  raise "direct call bypassed private class visibility"
rescue NoMethodError
  puts "direct call rejected"
end
