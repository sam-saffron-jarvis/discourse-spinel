# A container a builtin block loop reads from stays live for the whole loop:
# the String each_line/each_char/each_byte forms hold the receiver and the
# array of lines in temporaries, Hash#each holds the hash in one, and the
# block between two turns allocates. Every block here allocates before it
# looks at what it was handed, and every arm prints its iteration count as
# well as its content check: an arm that ends early shows up as a changed
# answer rather than as a passing test.

LINES = 300
CHARS = 300
CHURN = 200

def churn
  CHURN.times { "q" * 64 }
end

def make_lines
  (1..LINES).map { |i| "L#{i}" }.join("\n")
end

def make_chars
  (1..CHARS).map { |_i| "c" }.join
end

def make_hash
  h = {}
  (1..40).each { |i| h["k#{i}"] = "v#{i}" }
  h
end

# --- String#each_line: the receiver AND the array of lines it walks ---

text = make_lines
seen = 0
bad = 0
text.each_line do |l|
  churn
  seen += 1
  bad += 1 unless l.start_with?("L")
end
puts "each_line local seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_lines.each_line do |l|
  churn
  seen += 1
  bad += 1 unless l.start_with?("L")
end
puts "each_line temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_lines.each_line(chomp: true) do |l|
  churn
  seen += 1
  bad += 1 if l.end_with?("\n")
end
puts "each_line chomp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_lines.each_line("\n") do |l|
  churn
  seen += 1
  bad += 1 unless l.start_with?("L")
end
puts "each_line sep seen=#{seen} bad=#{bad}"

# --- String#each_char / each_byte / each_grapheme_cluster: the receiver ---

chars = make_chars
seen = 0
bad = 0
chars.each_char do |ch|
  churn
  seen += 1
  bad += 1 unless ch == "c"
end
puts "each_char local seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_chars.each_char do |ch|
  churn
  seen += 1
  bad += 1 unless ch == "c"
end
puts "each_char temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_chars.each_byte do |b|
  churn
  seen += 1
  bad += 1 unless b == 99
end
puts "each_byte temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_chars.each_grapheme_cluster do |g|
  churn
  seen += 1
  bad += 1 unless g == "c"
end
puts "each_grapheme_cluster temp seen=#{seen} bad=#{bad}"

# The loop answers its receiver, which is the same temporary it walked.
ret = make_chars.each_char { churn }
puts "each_char returns the receiver len=#{ret.length} head=#{ret[0, 3]}"
ret = make_lines.each_line { churn }
puts "each_line returns the receiver len=#{ret.length} head=#{ret[0, 3]}"

# --- Hash#each / #each_pair: the hash the loop reads its bound from ---

HCHURN = 400

seen = 0
bad = 0
make_hash.each do |k, v|
  HCHURN.times { "q" * 64 }
  seen += 1
  bad += 1 unless k.start_with?("k") && v.start_with?("v")
end
puts "Hash#each temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_hash.each_pair do |k, v|
  HCHURN.times { "q" * 64 }
  seen += 1
  bad += 1 unless k.start_with?("k") && v.start_with?("v")
end
puts "Hash#each_pair temp seen=#{seen} bad=#{bad}"

# a solo block parameter takes the [key, value] pair
seen = 0
bad = 0
make_hash.each do |pair|
  HCHURN.times { "q" * 64 }
  seen += 1
  bad += 1 unless pair.length == 2 && pair[0].start_with?("k")
end
puts "Hash#each solo param seen=#{seen} bad=#{bad}"

# --- Array#each_cons / #each_slice / #each_index / #cycle: the array ---

def make_array
  a = []
  (1..LINES).each { |i| a << i }
  a
end

seen = 0
bad = 0
make_array.each_cons(3) do |w|
  churn
  seen += 1
  bad += 1 unless w.length == 3
end
puts "each_cons temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_array.each_slice(3) do |w|
  churn
  seen += 1
  bad += 1 if w.empty?
end
puts "each_slice temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_array.each_index do |i|
  churn
  seen += 1
  bad += 1 unless i >= 0
end
puts "each_index temp seen=#{seen} bad=#{bad}"

seen = 0
bad = 0
make_array.cycle(2) do |x|
  churn
  seen += 1
  bad += 1 unless x >= 1
end
puts "cycle temp seen=#{seen} bad=#{bad}"

# --- leaving the loop early: the root pops on every way out ---

# The root is a cleanup-attribute declaration, so it pops when the statement
# expression is left -- off the end, through a `break`, or through a `return`
# from inside the block. A `raise` does not run cleanups and does not need to:
# the rescue emitters snapshot and restore the root count around the handler.

def first_line(text)
  text.each_line { |l| return l }
  "none"
end

def upto_third(text)
  seen = 0
  text.each_line do |l|
    churn
    seen += 1
    break if seen >= 3
  end
  seen
end

def broke_with(text)
  text.each_char { |ch| churn; break ch }
end

def raised_in(text)
  text.each_line { |_l| churn; raise "boom" }
rescue RuntimeError => e
  e.message
end

def first_key(hash)
  hash.each { |k, _v| return k }
  "none"
end

p first_line(make_lines)
p upto_third(make_lines)
p broke_with(make_chars)
p raised_in(make_lines)
p first_key(make_hash)

# the loop still walks correctly after all of that
seen = 0
make_lines.each_line { churn; seen += 1 }
puts "after early exits seen=#{seen}"
