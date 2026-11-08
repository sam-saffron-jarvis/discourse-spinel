$retry_class_loads += 1
module RetryOwner
  class Item
    def self.answer
      7
    end
  end
end
raise ArgumentError, "class load failed" if $retry_class_loads == 1
