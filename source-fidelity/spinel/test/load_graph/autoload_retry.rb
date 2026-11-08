# A feature that writes the autoloaded class/constant and then raises has
# not published that binding. Its next read must retry the feature, not
# bypass the pending autoload because the header/write already ran.
$retry_class_loads = 0
$retry_value_loads = 0
module RetryOwner
  autoload :Item, File.join(__dir__, "autoload_retry_class_lib")
  autoload :Value, File.join(__dir__, "autoload_retry_value_lib")
end
begin
  RetryOwner::Item.answer
rescue ArgumentError => error
  puts error.message
end
p defined?(RetryOwner::Item)
p $retry_class_loads
p RetryOwner::Item.answer
p $retry_class_loads
p RetryOwner::Item.answer
p $retry_class_loads
p require_relative("autoload_retry_class_lib.rb")
begin
  p RetryOwner::Value
rescue ArgumentError => error
  puts error.message
end
p defined?(RetryOwner::Value)
p $retry_value_loads
p RetryOwner::Value
p $retry_value_loads
p require_relative("autoload_retry_value_lib")
