# Bignum-receiver conveniences (digits/to_s(base)/even?/odd?/abs) and
# Integer#ord/#integer?. The Float#to_i-beyond-int64 line that used to sit
# here moved out: raise answers RangeError and promote answers the Bignum
# now (#4688), so it lives in float_to_int_out_of_range (raise, excluded
# from the promote run) and promote_float_to_int (promote).
x = 2 ** 100
p(x.digits)
p(x.to_s(16))
p(x.even?)
p(x.odd?)
p(x.abs)
y = x * -1
p(y.abs)
p(x.to_s(2).length)
p(5.integer?)
p(65.ord)
n = 7
p n.ord
p n.integer?
p 3.9.to_i
p(-2.9.to_i)
