# The FORMAT itself is a call rooting its own operands (a Symbol boxed into a
# poly parameter): the rooting statement used to land inside the format
# temp's `const char *_t = ...;` initializer, the sibling of #1508 on the
# arguments. Kernel#format / #sprintf and IO#printf.
module Msgs
  TABLE = { done: "done %d\n", fail: "fail" }
  def self.t(key)
    TABLE[key] || key.to_s
  end
end
def report(res)
  if res
    n = res[:deleted] || 0
    print sprintf(Msgs.t(:done), n)
    print format(Msgs.t(:done), n + 1)
    $stdout.printf(Msgs.t(:done), n + 2)
  else
    puts Msgs.t(:fail)
  end
end
report({ deleted: 3 })
report(nil)
puts Msgs.t("other")
