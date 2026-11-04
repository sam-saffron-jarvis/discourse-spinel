# Runtime Class parameters query their singleton table, not their instances.
class RuntimeQueryOwner
  def self.answer; 17; end
  def self.hidden; 19; end
  private_class_method :hidden
  class << self
    alias old_answer answer
    attr_accessor :level
  end
end
class RuntimeQueryChild < RuntimeQueryOwner
  private_class_method :answer
end
module RuntimeQueryModule
  def self.answer; 23; end
end
class RuntimeQueryProbe
  @effects = []
  def self.receiver
    @effects << :receiver
    RuntimeQueryOwner
  end
  def self.name(value)
    @effects << :name
    value.to_sym
  end
  def self.flag(value)
    @effects << :flag
    value
  end
  def self.query(receiver, name, include_private)
    receiver.respond_to?(name, include_private)
  end
  def self.exercise
    %w[answer hidden old_answer level level= name inherited new absent].each do |name|
      puts name
      puts query(RuntimeQueryOwner, name.to_sym, false)
      puts query(RuntimeQueryOwner, name.to_sym, true)
      puts query(RuntimeQueryChild, name.to_sym, false)
      puts query(RuntimeQueryChild, name.to_sym, true)
      puts query(RuntimeQueryModule, name.to_sym, false)
      puts query(RuntimeQueryModule, name.to_sym, true)
    end
    raise "query result" if query(receiver, self.name("absent"), flag(false))
    raise "operand evaluation" unless @effects == [:receiver, :name, :flag]
    puts "runtime Class query PASS"
  end
end
RuntimeQueryProbe.exercise
