module DeferredLiteralOwner
  OUTER = 41
end
DeferredLiteralOwner.autoload :Value, File.join(__dir__, "compact_deferred_value_lib.rb")
module OtherLiteralOwner
end
