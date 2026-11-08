# A compact class under a builtin has exact namespace identity even though
# builtin namespaces do not get an enclosing-class link in the class table.
class StandardError
end
class String
end
class StandardError::CompactMember
  def self.answer = 19
end
p StandardError::CompactMember.answer
p StandardError::CompactMember.name
p defined?(StandardError::CompactMember)
begin
  String::CompactMember
rescue NameError
  puts "wrong builtin owner rejected"
end
