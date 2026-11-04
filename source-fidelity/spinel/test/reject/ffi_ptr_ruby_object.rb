# A Ruby object in an ffi_func pointer slot has no address C can use: it
# passed the object itself, and memset wrote over its header.
module LibC
  ffi_func :memset, [:ptr, :int, :size_t], :ptr
end

class Frame
  def initialize = @w = 320
end

LibC.memset(Frame.new, 0, 8)
