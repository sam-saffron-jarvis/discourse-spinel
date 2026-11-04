# Regression: a user class that defines `call` with MORE required parameters
# than a poly `.call` site supplies must not shadow that site's callable fast
# path. The dispatch counts a user `call` as a candidate only when the site's
# argument count reaches its required arity (`argc >= nrequired`) and declines
# with none, so stepping aside for a four-parameter `call` left a two-argument
# `pred.call(host, port)` on a Proc read out of a container at the unresolved
# raise -- `undefined method 'call' for an instance of Proc` -- with no arm at
# all: not the Proc's, and not the formatter's either. The formatter here is
# the shape that surfaced it: a `Logger::Formatter`-style
# `call(severity, time, progname, message)` defined for the logger and never
# invoked on the predicate's path. A user `call` whose arity the site DOES
# reach still shadows the fast path (poly_call_legacy_abi_gate.rb covers the
# pre-arm that serves both from there).

class Formatter
  def call(severity, time, progname, message)
    "#{severity}: #{message}"
  end
end

module Seam
  PREDS = []

  def self.add(pred)
    PREDS << pred
    nil
  end

  def self.check(host, port)
    i = PREDS.length - 1
    while i >= 0
      return true if PREDS[i].call(host, port)
      i -= 1
    end
    false
  end
end

Seam.add(->(*args) { args.first == "example.com" && args[1] == 443 })
Seam.add(->(host, port) { host == "other.com" })
puts Seam.check("example.com", 443)
puts Seam.check("other.com", 80)
puts Seam.check("nowhere.test", 22)

# the formatter itself still dispatches
puts Formatter.new.call("INFO", nil, "app", "ready")

# Deliberately NO other user `call` in this program: one whose arity the
# site reaches would make the dispatch a candidate again and mask the gap
# (poly_call_legacy_abi_gate.rb covers that pre-arm).
