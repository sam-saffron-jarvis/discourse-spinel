class K
  attr_reader :v
  def initialize(v); @v = v; @tag = "k#{v}"; end
end
class J < K; end
def mkp = (1..40).map { |i| K.new(i) }
def mkmix = (1..40).map { |i| i.odd? ? K.new(i) : "s#{i}" }
def mkj = (1..40).map { |i| i == 7 ? J.new(i) : K.new(i) }
def mkstr = (1..40).map { |i| "s#{i}" }
held = mkp
puts "held_all=" + held.all?(K).to_s
puts "all=" + mkp.all?(K).to_s
puts "any=" + mkp.any?(K).to_s
puts "none=" + mkp.none?(K).to_s
puts "one=" + mkp.one?(K).to_s
puts "mix_all=" + mkmix.all?(K).to_s
puts "mix_any=" + mkmix.any?(String).to_s
puts "mix_none=" + mkmix.none?(Integer).to_s
puts "one_j=" + mkj.one?(J).to_s
puts "all_k_j=" + mkj.all?(K).to_s
puts "chain_all=" + mkp.reverse.all?(K).to_s
puts "str_all=" + mkstr.all?(String).to_s
puts "int_all=" + (1..40).map { |i| i * 2 }.all?(Integer).to_s
puts "count=" + mkp.count(K).to_s
