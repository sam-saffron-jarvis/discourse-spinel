$retry_value_loads += 1
module RetryOwner
  Value = 11
end
raise ArgumentError, "value load failed" if $retry_value_loads == 1
