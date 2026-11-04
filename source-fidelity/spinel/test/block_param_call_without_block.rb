# Calling a `&block` parameter that no block was passed for is a call on
# nil: CRuby raises NoMethodError. spinel answered the result's default
# value instead and carried on, both where the method is inlined at the
# call site and where it is a real function taking the proc (here because
# the proc is also stored away).

$keep = nil

def inl_stmt(&b)
  b.call(1)
  :after
end
def inl_value(&b)
  r = b.call(1)
  r
end
def inl_paren(&b) = b.(2)
def inl_index(&b) = b[3]
def inl_yield(&b) = b.yield(4)
def inl_string(&b)
  b.call("x") + "!"
end

def esc_value(&b)
  $keep = b
  b.call(1)
end
def esc_stmt(&b)
  $keep = b
  b.call(1)
  :after
end
def esc_index(&b)
  $keep = b
  b[3]
end
def esc_case_eq(&b)
  $keep = b
  b === 3
end

[-> { inl_stmt }, -> { inl_value }, -> { inl_paren }, -> { inl_index },
 -> { inl_yield }, -> { inl_string }, -> { esc_value }, -> { esc_stmt },
 -> { esc_index }, -> { esc_case_eq }].each do |f|
  begin
    p f.call
  rescue NoMethodError => e
    puts e.message
  end
end

p inl_stmt { |x| x }
p inl_value { |x| x + 1 }
p inl_paren { |x| x * 2 }
p inl_index { |x| x * 3 }
p inl_yield { |x| x * 4 }
p inl_string { |x| x * 2 }
p esc_value { |x| x + 1 }
p esc_index { |x| x + 1 }
p esc_case_eq { |x| x + 1 }
p $keep.call(10)
