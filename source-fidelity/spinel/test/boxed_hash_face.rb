# The rest of the Hash face on a receiver whose class is only known at run
# time: shift, replace, rehash and the bang transforms write back into the
# typed original (Symbol keys, String keys, the general hash); a default set
# through the box reaches the original, and the default readers and
# deconstruct_keys answer from it; a frozen original refuses shift, replace
# and a default before they run; a receiver that is an Array or a String at
# run time keeps its own shift and replace; a bang transform whose
# receiver is an expression evaluates it once; nil raises NoMethodError.
def attempt(name)
  yield
rescue => e
  puts "#{name}: #{e.class}"
end

h = {a: 1, b: 2, c: nil}
box = [h, 0][0]
attempt(:shift) { p box.shift; p h }
attempt(:replace) { p box.replace(z: 3, y: 4); p h }
attempt(:transform_keys!) { p box.transform_keys! { |k| :"#{k}#{k}" }; p h }
attempt(:transform_values!) { p box.transform_values! { |v| v * 10 }; p h }
attempt(:rehash) { p box.rehash.equal?(box) }
attempt(:default=) { box.default = 7; p [h[:nope], box[:nope], box.default, box.default(:k)] }
attempt(:deconstruct_keys) { p box.deconstruct_keys(nil) }
attempt(:default_proc) { p box.default_proc }

s = {"a" => 1}
sbox = [s, 0][0]
attempt(:str_shift) { p sbox.shift; p s }
attempt(:str_default=) { sbox.default = 5; p [s["x"], sbox["x"]] }

g = [{}, 0][0]
attempt(:general_default_proc=) { g.default_proc = proc { |_hh, k| k.to_s }; p g[:missing] }
attempt(:general_replace) { g.replace({q: 1}); p [g, g[:q]] }
attempt(:replace_entries) { box.replace({m: 5}); p [h, box[:m], h[:m]] }
attempt(:replace_self) { box.replace(box); p h }
attempt(:replace_other_kind) { box.replace([1]) }
attempt(:shift_empty) { p box.shift }

pair = [{a: 1}, {a: 2}, 0]
i = 0
pair[(i += 1) % 2].transform_values! { |v| v * 100 }
p pair
attempt(:shift_with_count) { box.shift(1) }

mixed = [[1, 2], +"ab", {k: 1}]
mixed.each { |m| p m.shift } rescue p $!.class
mixed.each { |m| p m.replace(m.class == String ? "cd" : m.class == Array ? [3] : {j: 2}) }

f = {a: 1}.freeze
fbox = [f, 0][0]
attempt(:frozen_shift) { fbox.shift }
attempt(:frozen_replace) { fbox.replace(b: 2) }
attempt(:frozen_default=) { fbox.default = 1 }

n = [nil, 0][0]
attempt(:nil_shift) { n.shift }
attempt(:nil_default) { n.default }
