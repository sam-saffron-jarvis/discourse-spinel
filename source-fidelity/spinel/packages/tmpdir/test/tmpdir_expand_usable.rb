# The usability check runs on the EXPANDED path, the one Dir.tmpdir hands
# back, not on $TMPDIR as the shell left it. The expansion is lexical, so a
# `..` after a symlink names a different directory than the raw string: here
# "<base>/ro/ln/.." resolves through the link to a writable directory while
# the expanded "<base>/ro" is not writable at all. Checking the raw path
# answered "<base>/ro", and Dir.mktmpdir then raised where CRuby falls back
# to /tmp (CRuby also warns "TMPDIR is not writable"; this package is silent
# about it, as it is about every other rejected candidate).
require "tmpdir"
require "fileutils"

base = File.join(Dir.tmpdir, "sp_tmpdir_usable_#{Process.pid}")
begin
  FileUtils.mkdir_p(File.join(base, "ro"))
  FileUtils.mkdir_p(File.join(base, "w"))
  File.symlink(File.join(base, "w"), File.join(base, "ro", "ln"))
  File.chmod(0o500, File.join(base, "ro"))

  ENV["TMPDIR"] = File.join(base, "ro", "ln", "..")
  p Dir.tmpdir == "/tmp"

  # a writable expanded path is still answered
  ENV["TMPDIR"] = File.join(base, "w", "..", "w")
  p Dir.tmpdir == File.join(base, "w")

  # and mktmpdir builds on what tmpdir answered
  ENV["TMPDIR"] = File.join(base, "ro", "ln", "..")
  made = Dir.mktmpdir("probe")
  p made.start_with?("/tmp/probe")
  Dir.rmdir(made)
ensure
  File.chmod(0o700, File.join(base, "ro")) rescue nil
  FileUtils.rm_rf(base)
end
