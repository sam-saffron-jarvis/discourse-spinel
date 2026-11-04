# spinel: int64
# The edge of the sp_int range itself: the largest Float that still fits,
# and the first that does not. The values are int64 boundaries, so this half
# stays off the 32-bit lane; float_to_int_out_of_range covers the raise on
# both widths.
# the largest Float that still fits, and the first that does not
p 9223372036854774784.0.to_i
begin; 9223372036854775808.0.to_i; rescue => e; puts "2**63: #{e.class}"; end
p(-9223372036854774784.0.to_i)
begin; (-9223372036854777856.0).to_i; rescue => e; puts "-2**63 - eps: #{e.class}"; end
