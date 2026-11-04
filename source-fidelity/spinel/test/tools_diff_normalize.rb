# The normalization `spinel diff` applies before comparing a CRuby run with a
# spinel run (tools/diff_normalize.rb), one rule per line: addresses, the
# program's directories, wall-clock times, the uncaught exception reduced to
# `Class: message` from either runtime's stderr form, and the spellings a
# pre-3.4 ruby writes differently from spinel. What is left alone is pinned
# too: Hash order, plain numbers, a warning-only stderr.
require_relative "../tools/diff_normalize"

p dn_addresses("#<Foo:0x00007f3a1c2b3d40 @a=1> and #<Bar::Baz:0x1234abcd>")
p dn_addresses("0x7f3a1c2b3d40 is an address, 0x1f is not, 0x1234 neither")
p dn_paths("/home/u/proj/app.rb:3 in /tmp/spinel-diff-app.rb.bin", ["/home/u/proj", "/tmp/spinel-diff-app.rb"])
p dn_paths("nothing here", ["", nil])
p dn_times("at 2026-09-20 15:04:05 +0900 and 2026-09-20 15:04:05.123456789 UTC and 2026-09-20 15:04:05")
p dn_times("2026-09-20 is a date, 15:04 a time: both stay")
p dn_ruby_pre34("{\"a\"=>1, :b=>2, :c?=>3}")
p dn_ruby_pre34("{\"a\" => 1, b: 2}")
p dn_ruby_pre34("undefined method `foo' for nil:NilClass")
p dn_ruby_pre34("undefined method `foo' for #<Foo:0xADDR @x=1>")
p dn_ruby_pre34("undefined method `foo' for Foo:Class")
p dn_ruby_pre34("undefined method `foo' for true:TrueClass")
p dn_ruby_pre34("undefined local variable or method `zzz' for main:Object")
p dn_ruby_pre34("wrong number of arguments (given 1, expected 0) in `bar'")
p dn_exception("app.rb:3:in 'Foo#bar': boom (RuntimeError)\n\tfrom app.rb:9:in '<main>'\n")
p dn_exception("app.rb:3:in `bar': boom (RuntimeError)\n\tfrom app.rb:9:in `<main>'\n")
p dn_exception("boom (RuntimeError)\n")
p dn_exception("undefined method 'zz' for nil (NoMethodError)\n")
p dn_exception("app.rb:1: warning: literal in condition\nvalue (ArgumentError)\n")
p dn_exception("app.rb:1: warning: something\n")
p dn_exception("")
p dn_exception("comparison of String with nil failed (ArgumentError)\n")
p dn_stdout("#<A:0x00007f00deadbeef> at 2026-01-02 03:04:05 +0000 in /w/x", ["/w"], false)
p dn_stdout("{\"k\"=>#<A:0x00007f00deadbeef>}", [], true)
p dn_stderr("/w/x.rb:1:in 'f': #<A:0x00007f00deadbeef> bad (TypeError)\n", ["/w"], false)
p dn_stdout("{1=>2, 3=>4}", [], true)
p dn_stdout("[3, 1, 2]", [], true)
