# A nested numeric table whose block parameter widens to a boxed value
# (the nil write) still has to box the row pointer. Assigning
# sp_PtrArray_get's void * straight into the sp_RbVal slot does not compile.
def walk
  rows = [[1.0, 2.0], [3.0, 4.0]]
  rows.each { |r| r = nil }
  rows
end

walk
