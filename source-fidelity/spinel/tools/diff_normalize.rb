# diff_normalize.rb -- the normalization `spinel diff` applies to both runs
# before comparing them. One place for every rule, so the rules can be read
# and tested as a unit (test/tools_diff_normalize.rb). Written in the spinel
# subset: spinel-diff is compiled by spinel itself.
#
# What is normalized, and why:
#   - `#<Foo:0x7f...>`        an address is never stable across processes
#   - absolute paths          the program's directory and the scratch directory
#   - a wall-clock time       `2026-09-20 15:04:05 +0900` and Time#inspect's
#                             fractional form
#   - stderr                  reduced to the one uncaught exception, as
#                             `Class: message`: CRuby prints `file:line:in
#                             'm': message (Class)` then a backtrace, spinel
#                             prints `message (Class)`; warnings are dropped
#   - Ruby-version spellings  when the reference ruby is older than 3.4:
#                             Hash#inspect's `=>` spacing and the NoMethodError
#                             wording, which spinel writes the 3.4 way
# What is NOT normalized, deliberately:
#   - Hash enumeration order  it is defined by the language; a difference is a bug
#   - object_id values        indistinguishable from data; see the README
#   - rand / pid values       spinel's generator is not CRuby's; see the README

# Every match of `re` in `s` replaced by `rep`.
def dn_gsub(s, re, rep)
  s.gsub(re, rep)
end

# Addresses inside `#<Class:0x...>` and bare `0x` hex runs of pointer length.
def dn_addresses(s)
  s = dn_gsub(s, /#<([A-Za-z_][A-Za-z0-9_:]*):0x[0-9a-f]+/, "#<\\1:0xADDR")
  dn_gsub(s, /\b0x[0-9a-f]{8,16}\b/, "0xADDR")
end

# The program's own directory and the scratch directory, longest first so a
# scratch path under the program's tree still reads as the scratch one.
def dn_paths(s, dirs)
  ds = dirs.select { |d| d && d.length > 0 }
  ds = ds.sort_by { |d| -d.length }
  ds.each { |d| s = s.gsub(d, "<DIR>") }
  s
end

# `YYYY-MM-DD HH:MM:SS` with an optional fraction and zone, which is what
# Time#to_s, Time#inspect and strftime's common forms print.
def dn_times(s)
  dn_gsub(s, /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(\.\d+)?( [+-]\d{4}| UTC)?/, "<TIME>")
end

# The spellings CRuby changed in 3.4, which spinel writes the new way:
#   {"a"=>1}                              -> {"a" => 1}
#   undefined method `x' for nil:NilClass -> undefined method 'x' for nil
#   undefined method `x' for #<Foo...>    -> undefined method 'x' for an instance of Foo
def dn_ruby_pre34(s)
  s = dn_gsub(s, /:([A-Za-z_][A-Za-z0-9_]*[?!]?)\s*=>\s*/, "\\1: ")   # {:a=>1} -> {a: 1}
  s = dn_gsub(s, /\s*=>\s*/, " => ")
  s = dn_gsub(s, /undefined method `([^']*)' for nil:NilClass/, "undefined method '\\1' for nil")
  s = dn_gsub(s, /undefined method `([^']*)' for (true|false):(TrueClass|FalseClass)/, "undefined method '\\1' for \\2")
  s = dn_gsub(s, /undefined method `([^']*)' for #<([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*)[^>]*>/, "undefined method '\\1' for an instance of \\2")
  s = dn_gsub(s, /undefined method `([^']*)' for ([A-Za-z_][A-Za-z0-9_:]*):Class/, "undefined method '\\1' for class \\2")
  s = dn_gsub(s, /undefined local variable or method `([^']*)' for main:Object/, "undefined local variable or method '\\1' for main")
  s = dn_gsub(s, /undefined local variable or method `([^']*)' for #<([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*)[^>]*>/, "undefined local variable or method '\\1' for an instance of \\2")
  s = dn_gsub(s, /`([^'`]*)'/, "'\\1'")   # every other backtick-quoted name
  s
end

# The one uncaught exception a run ended with, as `Class: message`, or "" when
# the run ended without one. CRuby's form is
#   path:LINE:in 'meth': message (Class)
#   \tfrom path:LINE:in ...
# (with the message possibly spanning lines until the ` (Class)` tail); spinel's
# is `message (Class)` alone. Warnings and everything else on stderr are not
# compared.
def dn_exception(err)
  lines = err.split("\n")
  first = -1
  i = 0
  while i < lines.length
    l = lines[i]
    if l =~ /\((\w+(::\w+)*)\)\s*$/ && !(l =~ /\A\s*from /) && !(l =~ /warning:/)
      first = i
      break
    end
    i += 1
  end
  return "" if first < 0
  msg = lines[first]
  cls = ""
  if msg =~ /\((\w+(::\w+)*)\)\s*$/
    cls = $1
    msg = msg.sub(/\s*\(\w+(::\w+)*\)\s*$/, "")
  end
  # CRuby's location prefix: `path:LINE:in 'meth': `
  msg = msg.sub(/\A.*?:\d+:in [`'][^'`]*': /, "")
  cls + ": " + msg
end

# stdout of a run, normalized. `dirs` are the paths to fold; `pre34` says the
# reference ruby predates 3.4 (the version spellings are folded on both sides,
# so a run that already writes them the new way is unchanged).
def dn_stdout(s, dirs, pre34)
  s = dn_addresses(s)
  s = dn_paths(s, dirs)
  s = dn_times(s)
  s = dn_ruby_pre34(s) if pre34
  s
end

# stderr of a run, normalized: the exception line only, folded the same way.
def dn_stderr(s, dirs, pre34)
  e = dn_exception(s)
  e = dn_addresses(e)
  e = dn_paths(e, dirs)
  e = dn_times(e)
  e = dn_ruby_pre34(e) if pre34
  e
end
