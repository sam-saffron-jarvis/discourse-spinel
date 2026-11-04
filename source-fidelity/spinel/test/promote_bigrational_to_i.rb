# promote answers the Bignum where raise reports it cannot fit the word
# (#4688's promise, the same one the Float conversions make).
br = Rational(2**70, 3)
nb = Rational(-(2**70), 3)
ex = Rational(2**70, 1)
p br.to_i
p nb.to_i
p ex.to_i
p br.to_int
pb = [Rational(2**70, 3), nil][0]
p pb.to_i
p pb.to_int
