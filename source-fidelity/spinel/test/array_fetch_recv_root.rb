# #fetch on a temporary receiver (a method's return, a chain) with an
# argument that allocates: the receiver must stay alive across the
# argument's evaluation. Arrays of every kind and Hashes alike.
class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end
def churn
  (1..60).map { |i| [K.new(i), "s#{i}"] }
  (1..30).map { |i| [i, i.to_s] }
  (1..30).map { |i| i * 2 }
  (1..30).map { |i| "t#{i}" }
  nil
end
def idx; churn; 5; end
def mkp = (1..40).map { |i| K.new(i) }
def mki = (1..40).map { |i| i * 10 }
def mks = (1..40).map { |i| "s#{i}" }
def mkf = (1..40).map { |i| i * 1.5 }
def mkh = (1..40).to_h { |i| ["k#{i}", i * 10] }
def mkhp = (1..40).to_h { |i| ["k#{i}", K.new(i)] }
def mksh = (1..40).to_h { |i| [:"k#{i}", i * 10] }
def mkts
  h = {}
  i = 1
  while i <= 40
    h["k#{i}"] = K.new(i)
    i += 1
  end
  h
end
begin
  puts "hash=" + mkh.fetch("k#{idx}").to_s
rescue KeyError => e
  puts "hash=" + e.class.to_s
end
puts "hash_def=" + mkh.fetch("k#{idx}", -1).to_s
begin
  puts "typed_hash=" + mkts.fetch("k#{idx}").v.to_s
rescue KeyError => e
  puts "typed_hash=" + e.class.to_s
end
puts "typed_hash_def=" + (mkts.fetch("k#{idx}", nil) || K.new(0)).v.to_s
puts "typed_hash_blk=" + (mkts.fetch("k#{idx}") { |k| K.new(0) }).v.to_s
puts "hash_blk=" + (mkh.fetch("k#{idx}") { |k| -1 }).to_s
puts "hashp=" + (mkhp.fetch("k#{idx}") { |k| nil }).v.to_s
puts "symh=" + mksh.fetch(:"k#{idx}").to_s
puts "symh_def=" + mksh.fetch(:"k#{idx}", -1).to_s
begin
  mkh.fetch("k#{idx + 100}")
rescue KeyError => e
  puts "hash_miss=" + e.message
end
puts "str=" + mks.fetch(idx)
puts "int=" + mki.fetch(idx).to_s
puts "flt=" + mkf.fetch(idx).to_s
held = mkp
puts "held=" + held.fetch(idx).v.to_s
puts "poly=" + mkp.fetch(idx).v.to_s
puts "poly_def=" + mkp.fetch(idx, nil).v.to_s
puts "poly_blk=" + (mkp.fetch(idx) { |i| nil }).v.to_s
puts "poly_neg=" + mkp.fetch(-idx).v.to_s
puts "poly_chain=" + mkp.reverse.fetch(idx).v.to_s
puts "poly_if_def=" + mkp.fetch((if churn then 5 else 4 end), nil).v.to_s
puts "int_def=" + mki.fetch(idx, -1).to_s
puts "int_blk=" + (mki.fetch(idx) { |i| -1 }).to_s
puts "int_if_def=" + mki.fetch((if churn then 5 else 4 end), -1).to_s
puts "int_if_blk=" + (mki.fetch((if churn then 5 else 4 end)) { |i| -1 }).to_s
puts "int_neg=" + mki.fetch(-idx).to_s
puts "str_def=" + mks.fetch(idx, "none")
puts "miss_def=" + mki.fetch(idx + 100, -1).to_s
puts "miss_blk=" + (mki.fetch(idx + 100) { |i| i * 2 }).to_s
begin
  mki.fetch(idx + 100)
rescue IndexError => e
  puts "miss_raise=" + e.message
end
