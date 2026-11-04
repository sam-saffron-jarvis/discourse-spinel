# `system(cmd)` as the last expression of a block: the block's value is the
# command's exit status as a boolean. The statement form of system is a
# compound (it builds the argv array inside braces), whose value is void, so
# the spliced block yielded void and the generated C did not build; assigning
# the result to a local first worked. Common in retry helpers.
def retry_until_ok
  return true if yield(1)
  false
end
p retry_until_ok { |i| ok = system("true"); ok }
p retry_until_ok { |i| system("true") }
p retry_until_ok { |i| system("false") }

def r; ok = yield(1); ok; end
p r { system("true") }
p r { system("false") }
p r { system("echo", "argv form") }

def rr(&b) = b.call(2)
p rr { |x| system("true") }

def each_two; yield 1; yield 2; end
res = []
each_two { |i| res << i; system("true") }
p res

q = proc { system("false") }
p q.call
