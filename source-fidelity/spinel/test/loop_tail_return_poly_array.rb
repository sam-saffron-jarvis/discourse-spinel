# A method whose tail is a `loop` left only by `return`, returning a poly
# array: the loop's boxed value was returned through the sp_PolyArray *
# slot and the C did not compile (#4836).

def settle(rows, cols)
  loop do
    before = rows
    rows &= cols
    return [rows, cols] if rows == before
  end
end
v = [7, "x"][0]
p settle(v, 3)
p settle(7, 3)
def first_word(ws)
  i = 0
  loop do
    w = ws[i]
    return w.upcase if w.size > 2
    i += 1
  end
end
p first_word(%w[a bb ccc])
def gen
  e = [1, 2].each
  loop do
    x = e.next
    return [x, "s"] if x > 5
  end
end
p gen
