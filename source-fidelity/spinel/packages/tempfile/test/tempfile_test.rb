require "tempfile"

# The block form: the file is open for reading and writing, and it is
# gone once the block ends.
seen = nil
result = Tempfile.create("probe") do |f|
  seen = f.path
  puts f.is_a?(File)
  puts File.exist?(f.path)
  f.write("hello")
  f.flush
  f.rewind
  puts f.read == "hello"
  :done
end
puts result == :done
puts !File.exist?(seen)

# The name is built under Dir.tmpdir, and carries the prefix, the date
# and the pid -- CRuby's Dir::Tmpname shape.
date = Time.now.strftime("%Y%m%d")
Tempfile.create("myapp-") do |f|
  base = File.basename(f.path)
  puts f.path.start_with?(Dir.tmpdir)
  puts base.start_with?("myapp-")
  puts base.include?(date)
  puts base.include?(Process.pid.to_s)
end

# The array form asks for a suffix, which is what a reader that looks at
# the extension needs.
Tempfile.create(["img", ".png"]) do |f|
  base = File.basename(f.path)
  puts base.start_with?("img")
  puts base.end_with?(".png")
end

# A second positional argument is the parent directory.
parent = Dir.mktmpdir
begin
  Tempfile.create("here", parent) do |f|
    puts File.dirname(f.path) == parent
  end
ensure
  Dir.rmdir(parent) if Dir.exist?(parent)
end

# The file is created with 0600: a temp file is not something other
# users on the machine get to read.
Tempfile.create("perm") do |f|
  puts (File.stat(f.path).mode & 0777) == 0600
end

# Two files in flight at once do not collide.
Tempfile.create("a") do |f1|
  Tempfile.create("a") do |f2|
    puts f1.path != f2.path
  end
end

# A raise inside the block still closes and removes the file.
leaked = nil
begin
  Tempfile.create("boom") do |f|
    leaked = f.path
    raise ArgumentError, "from the block"
  end
rescue ArgumentError => e
  puts e.message == "from the block"
end
puts !File.exist?(leaked)

# A block that closed the file itself is the ordinary case, not an error.
closed = nil
Tempfile.create("closed") do |f|
  closed = f.path
  f.write("x")
  f.close
end
puts !File.exist?(closed)

# Without a block the file is the caller's to remove, and it is still there.
f = Tempfile.create("kept")
begin
  puts File.exist?(f.path)
ensure
  f.close
  File.unlink(f.path)
end

# The file is owner-only, and `perm:` does not change that: CRuby's own
# create sets opts[:perm] = 0600 after merging the caller's options, so a
# caller asking for 0644 still gets a file nobody else can open.
Tempfile.create("mode") { |f| p (File.stat(f.path).mode & 0o777).to_s(8) }
Tempfile.create("mode", nil, perm: 0644) { |f| p (File.stat(f.path).mode & 0o777).to_s(8) }
