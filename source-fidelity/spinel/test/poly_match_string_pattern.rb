# `str.match("x")` on a run-time-typed receiver: the pattern is the ARGUMENT,
# built from the string the way CRuby's String#match builds it. The poly
# helper took whichever side was not a Regexp as the pattern, which for two
# strings is the RECEIVER -- so it matched the argument against a pattern made
# of the subject and answered no match for every such call.
h = { "s" => "hello world", "n" => 3 }
k = h["s"]
re = /w(or)ld/

p k.match("o w")
p k.match?("o w")
p k.match("zzz")
p k.match?("zzz")
p k.match(re)[1]
p re.match(k)[1]
p k.match?(re)
p re.match?(k)
p(k =~ /world/)
p(/world/ =~ k)
