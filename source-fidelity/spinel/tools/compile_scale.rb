# Compile-time scaling benchmark (#4847).
#
#   ruby tools/compile_scale.rb [--cc] [--check] K1 K2 ...
#
# Generates the synthetic program of tools/compile_scale_gen.rb at each K and
# times spinel's two phases on it: analysis (`--emit-rbs`, which runs the type
# inference and stops) and the full C emission (`-c`). With --cc the emitted C
# is also compiled; with --check the compiled binary's output is compared with
# CRuby's (it needs --cc).
#
# What to read is the growth between consecutive sizes, not the seconds: the
# absolute times depend on the machine, the ratio between K and 2K does not
# much. The program grows linearly in K (nodes and scopes), so a phase that
# is linear in the program shows x2 per doubling, and the analysis today shows
# x3.4 to x5.7.

require "tmpdir"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
SPINEL = File.join(ROOT, "spinel")
GEN = File.join(__dir__, "compile_scale_gen.rb")

cc = ARGV.delete("--cc")
check = ARGV.delete("--check")
ks = ARGV.map { |a| Integer(a) }
ks = [100, 200] if ks.empty?

def clock
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ok = yield
  [Process.clock_gettime(Process::CLOCK_MONOTONIC) - t, ok]
end

def run!(*cmd)
  system(*cmd, out: File::NULL, err: File::NULL)
end

rows = []
Dir.mktmpdir("spinel-scale") do |dir|
  ks.each do |k|
    prog = File.join(dir, "scale_#{k}.rb")
    File.write(prog, IO.popen([RbConfig.ruby, GEN, k.to_s], &:read))
    lines = File.foreach(prog).count
    ta, ok_a = clock { run!(SPINEL, prog, "--emit-rbs", "-o", File.join(dir, "s#{k}.rbs")) }
    cfile = File.join(dir, "s#{k}.c")
    tc, ok_c = clock { run!(SPINEL, prog, "-c", "--no-line-map", "-o", cfile) }
    abort "compile_scale: spinel failed at K=#{k}" unless ok_a && ok_c
    row = { k: k, lines: lines, analyze: ta, emit: tc, csize: File.size(cfile) }
    if cc
      bin = File.join(dir, "s#{k}.bin")
      tb, ok_b = clock { run!(SPINEL, prog, "-o", bin) }
      abort "compile_scale: build failed at K=#{k}" unless ok_b
      row[:build] = tb
      if check
        want = IO.popen([RbConfig.ruby, prog], &:read)
        got = IO.popen([bin], &:read)
        abort "compile_scale: K=#{k} output differs from CRuby" unless want == got
        row[:check] = "ok"
      end
    end
    rows << row
  end
end

cols = [[:k, "K"], [:lines, "lines"], [:analyze, "analyze s"], [:emit, "emit s"],
        [:csize, "C MB"]]
cols << [:build, "build s"] if cc
cols << [:check, "vs CRuby"] if check
fmt = lambda do |key, v|
  case key
  when :analyze, :emit, :build then format("%.2f", v)
  when :csize then format("%.1f", v / 1_048_576.0)
  else v.to_s
  end
end
puts cols.map { |_, h| h.rjust(10) }.join
rows.each_with_index do |r, i|
  puts cols.map { |key, _| fmt.(key, r[key]).rjust(10) }.join
  next if i.zero?
  prev = rows[i - 1]
  scale = r[:k].to_f / prev[:k]
  growth = [:analyze, :emit, :csize, (cc ? :build : nil)].compact.map do |key|
    "#{key} x#{format('%.1f', r[key] / prev[key])}"
  end
  puts "  K x#{format('%.1f', scale)}: #{growth.join(', ')}"
end
