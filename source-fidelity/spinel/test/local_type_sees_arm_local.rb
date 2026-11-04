# infer_write_types re-derives every non-param local from scratch each round:
# it resets them to UNKNOWN, then walks the writes in NODE order. A read
# reached BEFORE its own write therefore answered UNKNOWN, and ty_unify drops
# UNKNOWN -- so an if-arm ending in such a read let the OTHER arm's narrower
# type stand. The local took that type and the value was converted into it.
#
# The tell was that hoisting the same assignment out of the arm, which only
# changes node order, already gave the right answer.

def multi(s)
  v = if s.length > 9
        9
      else
        t = s.upcase          # written AFTER the enclosing `v =` in node order
        t
      end
  v
end

p multi("ab")
p multi("a long string here")

# the same shape one level out: the write is in an else branch
def outer(flag, s)
  if flag
    v = 0
  else
    v = if s.length > 9
          9
        else
          t = s.upcase
          t
        end
  end
  v
end

p outer(false, "ab")
p outer(true, "ab")

# hoisted: this always worked, and must keep working
def hoisted(s)
  t = s.upcase
  v = if s.length > 9
        9
      else
        t
      end
  v
end

p hoisted("ab")

# a single-statement arm: also always worked
def single(s)
  v = if s.length > 9
        9
      else
        s.upcase
      end
  v
end

p single("ab")
