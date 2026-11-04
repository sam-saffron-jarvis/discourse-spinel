# The IO family -- an IO, a File, a File::Stat and a Dir handle -- answers
# Object's protocol like any object: to_s is #<Class:0xADDR>, <=> is 0 for the
# same object and nil otherwise (two File::Stat handles order by mtime), hash
# and object_id are the identity; the same answers through a boxed handle.
require "tmpdir"

def addr(s)
  s.gsub(/0x\h{16}/, "0xADDR")
end

Dir.mktmpdir do |dir|
  a = File.join(dir, "a.txt")
  b = File.join(dir, "b.txt")
  File.write(a, "a")
  File.write(b, "b")
  File.utime(Time.at(1_000_000), Time.at(1_000_000), a)
  File.utime(Time.at(2_000_000), Time.at(2_000_000), b)

  r, w = IO.pipe
  f = File.open(a)
  d = Dir.open(dir)
  sa = File.stat(a)
  sb = File.stat(b)

  # to_s is Object's render; inspect stays each handle's own
  p [addr(r.to_s), addr(f.to_s), addr(d.to_s), addr(sa.to_s), addr($stdout.to_s), addr(STDERR.to_s)]
  p [r.to_s == r.inspect, f.to_s == f.inspect, d.to_s == d.inspect, sa.to_s == sa.inspect]
  p [r.to_s.frozen?, f.to_s.equal?(f.to_s)]
  puts addr("#{f}"), addr("#{d}"), addr("#{sa}"), addr("pipe: #{r}")
  puts addr(f.to_s)
  puts [f, d, sa].map { |o| addr(o.to_s) }
  puts addr([r, d].join(" "))

  # <=>: the same object is 0, anything else nil; File::Stat orders by mtime
  d2 = Dir.open(dir)
  p [r <=> r, r <=> w, f <=> f, f <=> r, d <=> d, d <=> d2]
  p [sa <=> sa, sa <=> sb, sb <=> sa, sa <=> File.stat(a), sa <=> f, f <=> sa]
  p [sa <=> 1, f <=> "x", d <=> 1, r <=> nil, d <=> nil, sa <=> nil, f <=> Random.new, d <=> Random.new]
  mixed = [f, r, d, sa, sb, 1, nil, "s"]
  p mixed.map { |o| f <=> o }
  p mixed.map { |o| d <=> o }
  p mixed.map { |o| sa <=> o }
  p mixed.map { |o| o <=> sb }
  p mixed.map { |o| o <=> o }
  p [[sb, sa].sort == [sa, sb], [sa, sb].max.equal?(sb), [sa, sb].min.equal?(sa)]
  begin
    [f, r].sort
  rescue ArgumentError => e
    p [e.class, e.message]
  end
  c1 = File.join(dir, "c1.txt")
  c2 = File.join(dir, "c2.txt")
  File.write(c1, "1")
  sleep 0.01
  File.write(c2, "2")
  p [File.stat(c1) <=> File.stat(c2), File.stat(c2) <=> File.stat(c1), File.stat(c1) <=> File.stat(c1)]
  d2.close

  # == / eql? / equal? keep their meaning next to <=>
  p [sa == File.stat(a), sa.eql?(File.stat(a)), sa.equal?(sa), sa == sb, f == f, f == r, d == d, d == 1]

  # hash and object_id are the identity, stable across calls
  p [r.hash.is_a?(Integer), r.hash == r.hash, r.hash == w.hash, f.hash == f.hash, d.hash == d.hash]
  p [sa.hash == sa.hash, sa.hash == File.stat(a).hash, sa.object_id == sa.object_id]
  p [r.object_id == r.object_id, r.__id__ == r.object_id, r.object_id == w.object_id, d.object_id == d.object_id]
  h = { r => :r, f => :f, d => :d, sa => :sa }
  p [h[r], h[f], h[d], h[sa], h[w], h[File.stat(a)], h.size]

  # a closed handle still has its identity
  r.close
  w.close
  f.close
  d.close
  p [addr(r.to_s), r <=> r, r <=> w, r.hash.is_a?(Integer), addr(f.to_s), f <=> f, addr(d.to_s), d <=> d, d.hash == d.hash]

  # the standard streams are one object under both names
  p [$stdout <=> STDOUT, $stdout <=> $stderr, $stdout.hash == STDOUT.hash, $stdout.object_id == STDOUT.object_id, STDIN <=> $stdin]

  # a handle-typed slot holding nil is nil: 0 against nil, nil against the rest, "" to render
  r2, w2 = IO.pipe
  none = r2.wait_readable(0)
  p [none, none <=> nil, none <=> none, none <=> 1, none <=> r2, none <=> mixed[6], none.to_s, "#{none}", none.hash == nil.hash]
  p [none != nil, r2 != nil, none.nil?, r2.nil?]
  r2.close
  w2.close
end
