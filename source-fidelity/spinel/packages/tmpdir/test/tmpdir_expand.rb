require "tmpdir"

# CRuby hands back File.expand_path of the candidate, not $TMPDIR as it
# found it: a trailing separator is dropped, and macOS sets $TMPDIR in
# exactly that form ("/var/folders/.../T/").
ENV["TMPDIR"] = "/tmp/"
puts Dir.tmpdir == "/tmp"

ENV["TMPDIR"] = "/tmp///"
puts Dir.tmpdir == "/tmp"

# A path that needs no expanding is returned unchanged.
ENV["TMPDIR"] = "/tmp"
puts Dir.tmpdir == "/tmp"

# The resolution is lexical: "." and ".." components are cancelled the
# way expand_path cancels them, without asking the filesystem.
ENV["TMPDIR"] = "/tmp/."
puts Dir.tmpdir == "/tmp"

ENV["TMPDIR"] = "/tmp/../tmp"
puts Dir.tmpdir == "/tmp"

# A relative $TMPDIR is made absolute, so the answer goes on naming the
# same directory after the process chdirs.
ENV["TMPDIR"] = "."
here = Dir.tmpdir
puts here.start_with?("/")
puts here == Dir.pwd

# The expanded path is what mktmpdir builds on, so the directory it makes
# carries no doubled separator and its parent IS the string Dir.tmpdir
# answered -- the comparison mktmpdir's own parent check makes.
ENV["TMPDIR"] = "/tmp/"
d = Dir.mktmpdir
begin
  puts !d.include?("//")
  puts File.dirname(d) == Dir.tmpdir
ensure
  Dir.rmdir(d) if Dir.exist?(d)
end
