class NullableStoredOwner
  def self.seed(values)
    @values = values
  end
end
class NullableStoredChild < NullableStoredOwner
end
class NullableStoredBody
  def initialize(body)
    @body = body
  end
  def invoke(receiver)
    @body.call(receiver)
  end
end
NullableStoredOwner.seed({value: 17})
key = :value
stored = NullableStoredBody.new(->(receiver) { receiver.instance_variable_get(:@values)[key] })
begin
  puts stored.invoke(NullableStoredChild).inspect
rescue NoMethodError
  puts 'stored nil receiver'
end
puts stored.invoke(NullableStoredOwner).inspect
