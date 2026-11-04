# A yielder that keeps `result = yield` and answers it, reached through a
# forwarding block (`wrap { yield }`) from sites whose blocks answer
# different types. `result` widens to poly across the sites, but the
# forwarding block's tail is a yield whose cached node type is one site's,
# so every site boxed the value as the first site's kind (#4495). The
# value at a site is what the block one level out answers.
module Db
  def self.with_connection
    r = 1
    result = yield
    r = 2
    result
  end
  def self.with_conn_arg(x)
    result = yield x
    result
  end
end

class Executor
  def wrap
    Db.with_connection { yield }
  end
  def wrap_arg(x)
    Db.with_conn_arg(x) { |v| yield v }
  end
end

def count(n) = n + 1
def name(s) = "n:#{s}"
def pick(h, k) = h[k]

ex = Executor.new
slots = { "a" => 1, "b" => "two" }
p ex.wrap { count(41) }
p ex.wrap { name("x") }
p ex.wrap { nil }
p ex.wrap { [1, 2] }
p ex.wrap { pick(slots, "b") }
p ex.wrap { pick(slots, "zz") }
p ex.wrap { {k: 1} }
p ex.wrap_arg(3) { |v| v * 2 }
p ex.wrap_arg(3) { |v| "v#{v}" }
r = ex.wrap { 1.5 }
p r
