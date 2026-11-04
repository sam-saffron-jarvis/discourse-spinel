# #542. Method param defaulted to int when no caller passed a
# concretely-typed argument. The body's `row["id"]` then emitted
# the literal 0 with a "cannot resolve" warning and the method
# silently produced wrong output -- `id=0` for the repro,
# all-default-value Article rows in the roundhouse real-blog.
# Sam Ruby ran 30 lines of type_seeds.rb to work around this.
#
# Fix (Option 2 + cast + NULL-guard, per the issue's design
# discussion):
#
# 1. analyze: new `infer_hash_param_from_body` pass scans each
#    method body for `param[StringNode/SymbolNode]` access. When
#    found and the param's slot is still at the int/nil default,
#    widen to `str_poly_hash` (string keys) or `sym_poly_hash`
#    (symbol keys). Runs in the inference fixpoint alongside
#    `infer_string_param_from_body`.
#
# 2. codegen: `compile_call_args_with_defaults` adds a hash-typed
#    param cast arm. When the param's static type is a hash and
#    the arg's inferred type is int/nil/poly, cast at the call
#    site so the C signature accepts the call without an
#    "incompatible integer to pointer conversion" error.
#
# 3. runtime: NULL-guards in the hash getters
#    (`sp_StrPolyHash_get`, `sp_SymPolyHash_get`,
#    `sp_StrIntHash_get`, `sp_StrStrHash_get`,
#    `sp_IntStrHash_get`, `sp_SymIntHash_get`,
#    `sp_SymStrHash_get`, `sp_PolyPolyHash_get`) return the
#    slot's default sentinel (`sp_box_nil`, `0`, `sp_str_empty`)
#    instead of dereferencing a NULL hash header.
#
# The combination addresses Sam's composition concern: typed
# callers continue to build the right hash variant; untyped
# callers cast their nil/int values to NULL of the param's
# pointer type, and the body's `row["k"]` raises NoMethodError
# on the nil, as CRuby does (#4485; the read used to answer nil
# and the consumer printed `nil.to_s -> ""`). The silent emit-0
# is gone either way.

# Single untyped caller: param widens from body usage alone, no
# type_seeds.rb seeding required.
def consume(row)
  puts "id=" + row["id"].to_s
end

class Box
  attr_accessor :contents
end

b = Box.new
begin
  consume(b.contents)  # untyped (uninit ivar = nil); body inference widens param
rescue NoMethodError => e
  puts e.class         # the read on nil raises, as in CRuby (#4485)
end

# Mixed callers: typed hash literal + untyped value -- previously
# the typed caller's widening would lock the param at sp_StrPolyHash*
# and the untyped caller would fail C compile. Now the call-site
# cast lets the untyped caller through.
def fetch(row)
  puts "title=" + row["title"].to_s
end

fetch({"title" => "Real Hash"})
# the nil caller reaches the body's read, which raises as CRuby's does (#4485)
begin
  fetch(b.contents)
rescue NoMethodError => e
  puts e.class
end
fetch({"title" => "Another Real"})

# Symbol-keyed lookup widens to sym_poly_hash via the same
# inference path.
def grab(opts)
  puts "name=" + opts[:name].to_s
end

grab({name: "Sym Hash"})
begin
  grab(b.contents)
rescue NoMethodError => e
  puts e.class
end
