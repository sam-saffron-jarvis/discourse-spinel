# A method containing `yield` that ALSO uses its `&blk` as a value.
#
# `yield` marks a method for inlining at its call sites, where the block is
# spliced and the &blk slot is virtual -- no storage is emitted for it. Every
# use of blk that is not a call still named that storage, so the C failed to
# compile: `use of undeclared identifier 'lv_blk'` (or `_cell_blk` when a
# nested proc captured it). The escape analysis already refuses to splice such
# a method; a literal `yield` set the inline mark anyway and nothing took it
# back. Lowering it to the real &block-proc form is what the self-recursive and
# the Thread-body yielders already do.

# Handed to another method.
def pass_it(b) = b.call(2)

def yields_and_passes(&blk)
  yield(0)
  pass_it(blk)
end
p yields_and_passes { |i| i * 10 }

# Assigned to a local.
def yields_and_assigns(&blk)
  yield(1)
  q = blk
  q.call(3)
end
p yields_and_assigns { |i| i + 100 }

# Captured by a nested proc: blk needs a heap cell, which the inline path
# named as `_cell_blk` without allocating one.
def yields_and_captures(&blk)
  yield(4)
  t = Thread.new { blk.call(5) }
  t.value
end
p yields_and_captures { |i| i * 3 }

# The two uses in DIFFERENT branches -- neither arm sees both, the method still
# has to carry the block.
def yields_or_passes(n, &blk)
  if n > 0
    yield(n)
  else
    pass_it(blk)
  end
end
p [yields_or_passes(7) { |i| i }, yields_or_passes(0) { |i| i }]

# The block is still the caller's: what it writes to an enclosing local has to
# arrive, through either use. (Both sites pass an Integer on purpose -- a block
# called with a Symbol at one site and an Integer at another mistypes the
# argument, which is a separate defect and reproduces with no `yield` in sight.)
seen = []
def yields_then_passes(&blk)
  yield(11)
  pass_it(blk)
  nil
end
yields_then_passes { |x| seen << x }
p seen

# The engine shape this came from: a sequential path driven by `yield` and a
# threaded path that hands the same block to Thread.new.
def each_index(n, nthreads, &blk)
  if nthreads <= 1
    i = 0
    while i < n
      yield(i, 0)
      i += 1
    end
    return nil
  end
  workers = []
  w = 0
  while w < nthreads
    workers << Thread.new(w) { |wid| j = wid; while j < n; blk.call(j, wid); j += nthreads; end }
    w += 1
  end
  workers.each { |t| t.join }
  nil
end

seq = 0
each_index(6, 1) { |i, _w| seq += i }
par = 0
# the block runs on three threads at once: the sum is under a lock, or an
# update is lost now and then (CI read 12 for 15 once)
lock = Mutex.new
each_index(6, 3) { |i, _w| lock.synchronize { par += i } }
p [seq, par]

# `case blk` is a VALUE use: CaseNode spells its subject `predicate`, the same
# field name an if/unless/while/until gives its condition, so exempting every
# `predicate` from the value-use test put this shape straight back to naming an
# undeclared lv_blk. Pattern matching (`case/in`) spells it that way too.
def yields_and_cases(&blk)
  yield(1)
  case blk
  when Proc then blk.call(2)
  else 0
  end
end
p yields_and_cases { |i| i * 10 }

def yields_and_case_ins(&blk)
  yield(1)
  case blk
  in Proc => p1 then p1.call(3)
  end
end
p yields_and_case_ins { |i| i * 5 }

# A condition and a value use of the same block in one method: the condition is
# still folded at the site that has one, the value use still needs the proc.
def yields_cases_and_assigns(&blk)
  yield(1) if blk
  r = case blk
      when Proc then 1
      else 0
      end
  q = blk
  [r, q.call(4)]
end
p yields_cases_and_assigns { |i| i }

# Pinned: the shapes that always compiled must keep doing so. A `yield` beside
# a plain `blk.call` is still spliced, and `yield` alone is untouched.
def yields_and_calls(&blk)
  yield(1)
  blk.call(2)
end
p yields_and_calls { |i| i * 7 }

def yields_only
  yield(9)
end
p yields_only { |i| i - 1 }
