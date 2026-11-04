# A `break` (or `next`) that leaves a begin/ensure region opened inside a
# while, until, begin..end while or `loop do` runs that ensure body first,
# and an ensure outside the loop still runs once, when its own region ends.
# On 4ea42f77 lines 2-11 skip the ensure body on the leaving iteration (line
# 8 also misses the ensure's own `return`); lines 1, 12 and 13 already print
# what the .expected holds (line 1: a break from an ensure opened inside a
# rescue body leaves that rescue exactly once).
def t0
  i = 0
  while i < 5
    i += 1
    begin
      raise "inner"
    rescue
      begin
        break if i == 2
      ensure
        i += 0
      end
    end
  end
  begin
    raise "later"
  rescue => e
    [i, e.message, $!.message]
  end
end
p t0

def t1
  log = []
  x = while true
    begin
      break 5
    ensure
      log << :e1
    end
  end
  [x, log]
end
p t1
def t2
  log = []
  i = 0
  r = loop do
    i += 1
    begin
      begin
        break i * 10 if i == 3
      ensure
        log << [:in, i]
      end
    ensure
      log << [:out, i]
    end
  end
  [r, log]
end
p t2
def t3
  log = []
  begin
    [1, 2].each do |k|
      while true
        begin
          break
        ensure
          log << [:w, k]
        end
      end
      log << [:after, k]
    end
  ensure
    log << :outer
  end
  log
end
p t3
def t4
  log = []
  i = 0
  until i > 5
    i += 1
    begin
      raise "x" if i == 2
      break if i == 4
    rescue
      log << :resc
      next
    ensure
      log << [:ens, i]
    end
  end
  log
end
p t4
def t5
  log = []
  begin
    i = 0
    while i < 3
      i += 1
      begin
        break if i == 2
      ensure
        log << [:inner, i]
      end
    end
    log << :loop_done
  ensure
    log << :outer_once
  end
  log
end
p t5
def t6
  log = []
  j = 0
  begin
    j += 1
    begin
      break if j == 2
    ensure
      log << j
    end
  end while j < 5
  log
end
p t6
def t7
  i = 0
  while true
    i += 1
    begin
      break
    ensure
      return :from_ensure if i == 1
    end
  end
  :fell
end
p t7
def t8
  log = []
  while true
    begin
      begin
        raise "boom"
      rescue
        break
      end
    ensure
      log << :e8
    end
  end
  log
end
p t8
def t10
  log = []
  i = 0
  r = loop do
    i += 1
    begin
      next if i == 1
      break i * 100 if i == 3
    ensure
      log << i
    end
  end
  [r, log]
end
p t10
def t11
  log = []
  l = -> {
    loop do
      begin
        break
      ensure
        log << :e
      end
    end
    :after
  }
  [l.call, log]
end
p t11
def t12
  log = []
  x = loop do
    break :plain
  end
  y = loop do
    begin
      raise StopIteration
    ensure
      log << :stop
    end
  end
  [x, y, log]
end
p t12
p((loop { break 7 }))
