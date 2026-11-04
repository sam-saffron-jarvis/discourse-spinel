# An exception leaving a begin..ensure belongs to the nearest enclosing
# HANDLER, which is not always the enclosing ensure. A `begin ... rescue`
# sitting between the two catches it in Ruby; the ensure epilogue handed it
# straight to the outer ensure instead, which walked past the rescue, ran the
# outer ensure twice and killed the program. Dir.chdir's block splice is a
# value-position begin/ensure, so nesting two of them around a rescue was
# enough.

def tracer(log)
  x = (begin
    begin
      y = (begin
        raise "inner"
      ensure
        log << :ens2
      end)
      log << [:y, y]
    rescue RuntimeError => e
      log << e.message
    end
    1
  ensure
    log << :ens1
  end)
  log << [:x, x]
end

log = []
tracer(log)
p log

# the rescue is the OUTER one: the inner ensure still runs first
log2 = []
begin
  (begin
    raise "boom"
  ensure
    log2 << :ens
  end)
rescue RuntimeError => e
  log2 << e.message
end
p log2

# no intervening rescue: the outer ensure runs and the exception leaves
log3 = []
begin
  (begin
    (begin
      raise "deep"
    ensure
      log3 << :inner
    end)
  ensure
    log3 << :outer
  end)
rescue RuntimeError => e
  log3 << e.message
end
p log3

# A non-matching rescue between the two: it re-raises past itself. Written in
# the statement form: a value-position begin/ensure whose arms answer
# different types does not compile ("incompatible types when assigning to
# sp_PolyArray * from sp_RbVal"), a separate pre-existing gap.
log4 = []
begin
  begin
    begin
      begin
        raise ArgumentError, "arg"
      ensure
        log4 << :ens2
      end
    rescue TypeError
      log4 << :wrong
    end
  ensure
    log4 << :ens1
  end
rescue ArgumentError => e
  log4 << e.message
end
p log4

# a deferred return still leaves through the ensures, not through a rescue
def deferred(log)
  begin
    begin
      begin
        return :returned
      ensure
        log << :r_ens2
      end
    rescue RuntimeError
      log << :r_rescue
    end
  ensure
    log << :r_ens1
  end
end
log5 = []
p deferred(log5)
p log5

# retry still works through the same shape
attempts = 0
log6 = []
begin
  attempts += 1
  (begin
    raise "retry me" if attempts < 2
    :ok
  ensure
    log6 << :ens
  end)
rescue RuntimeError
  retry
end
p [attempts, log6]
