# A key names a keyword parameter, never a positional one of the same name,
# and the refusals come in CRuby's order and words: the positional count
# (naming the required keywords), a missing keyword, an unknown one.
def f(x, k: 1) = [x, k]
def req_kw(x, k:) = [x, k]
def g(x, k: 1) = [x, k]
[-> { f(x: 2) }, -> { f(1, x: 2) }, -> { req_kw(k: 2) }, -> { g(5) }, -> { f(1, k: 3) }].each do |pr|
  begin
    p pr.call
  rescue ArgumentError => e
    p e.message
  end
end
def h(x, k:) = 1
def h2(x, a:, b:) = 1
def h3(x, k: 1) = 1
[-> { h(1, 2, k: 3) }, -> { h(k: 3) }, -> { h(1, 2) }, -> { h2(a: 1, b: 2) }, -> { h2(1, 2, a: 1, b: 2) }, -> { h3(1, 2) }, -> { h(1) }, -> { h(x: 1) }].each do |pr|
  begin; p pr.call; rescue ArgumentError => e; p e.message; end
end
def f9(x, k:) = 1
def g9(x, k: 1) = 1
[->{ f9(1, z: 1) }, ->{ f9(z: 1) }, ->{ g9(z: 1) }, ->{ f9(1, k: 1, z: 2) }].each { |pr| begin; pr.call; rescue ArgumentError => e; p e.message; end }
