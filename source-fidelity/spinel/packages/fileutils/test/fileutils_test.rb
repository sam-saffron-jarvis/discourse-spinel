# The bundled fileutils: what a program that requires it actually calls.
# Every answer here is CRuby's, generated from it -- the point of the package
# is that these calls mean the same thing under both.
require "fileutils"
require "tmpdir"

root = File.join(Dir.tmpdir, "sp_fileutils_#{Process.pid}")

begin
  # mkdir_p makes every missing component and is not an error twice over,
  # which is the whole difference from Dir.mkdir.
  # (paths are printed relative to root: the absolute ones carry a pid)
  made = FileUtils.mkdir_p(File.join(root, "a", "b", "c"))
  p made.map { |x| x.sub(root, "<root>") }
  p Dir.exist?(File.join(root, "a", "b", "c"))
  p FileUtils.mkdir_p(File.join(root, "a", "b", "c")).length
  p FileUtils.mkdir_p([File.join(root, "x"), File.join(root, "y")]).length
  p Dir.exist?(File.join(root, "y"))

  # a relative path rebuilds as relative, an absolute one as absolute
  Dir.chdir(root) do
    FileUtils.mkdir_p("rel/one/two")
    p Dir.exist?("rel/one/two")
  end

  f = File.join(root, "a", "f.txt")
  File.write(f, "hello")

  # cp into a directory takes the basename; cp onto a path uses the path
  FileUtils.cp(f, File.join(root, "x"))
  p File.read(File.join(root, "x", "f.txt"))
  FileUtils.cp(f, File.join(root, "y", "renamed.txt"))
  p File.read(File.join(root, "y", "renamed.txt"))
  p FileUtils.identical?(f, File.join(root, "x", "f.txt"))

  # mv
  FileUtils.mv(File.join(root, "y", "renamed.txt"), File.join(root, "y", "moved.txt"))
  p File.exist?(File.join(root, "y", "renamed.txt"))
  p File.read(File.join(root, "y", "moved.txt"))

  # touch creates, and does not complain the second time
  t = File.join(root, "touched")
  p File.exist?(t)
  FileUtils.touch(t)
  p File.exist?(t)
  FileUtils.touch(t)
  p File.size(t)

  # rm and rm_f: the plain one raises on what is not there, the forced one does not
  FileUtils.rm(File.join(root, "x", "f.txt"))
  p File.exist?(File.join(root, "x", "f.txt"))
  begin
    FileUtils.rm(File.join(root, "no", "such", "file"))
    puts "no raise"
  rescue StandardError
    puts "raised"
  end
  FileUtils.rm_f(File.join(root, "no", "such", "file"))
  puts "rm_f quiet"

  # cp_r copies a tree
  FileUtils.cp_r(File.join(root, "a"), File.join(root, "a_copy"))
  p File.read(File.join(root, "a_copy", "f.txt"))
  p Dir.exist?(File.join(root, "a_copy", "b", "c"))

  # rm_rf takes the tree down, and is quiet about one that is already gone
  FileUtils.rm_rf(File.join(root, "a_copy"))
  p Dir.exist?(File.join(root, "a_copy"))
  FileUtils.rm_rf(File.join(root, "a_copy"))
  puts "rm_rf quiet"

  # a symlink to a directory is unlinked, not followed: the tree it points at
  # survives, which is the accident the check exists to prevent
  keep = File.join(root, "keep")
  FileUtils.mkdir_p(keep)
  File.write(File.join(keep, "survivor.txt"), "still here")
  link_dir = File.join(root, "linkdir")
  FileUtils.mkdir_p(link_dir)
  File.symlink(keep, File.join(link_dir, "ln"))
  FileUtils.rm_rf(link_dir)
  p Dir.exist?(link_dir)
  p File.read(File.join(keep, "survivor.txt"))

  # chmod
  cf = File.join(root, "mode.txt")
  File.write(cf, "x")
  FileUtils.chmod(0o600, cf)
  p (File.stat(cf).mode & 0o777).to_s(8)

  p FileUtils.uptodate?(cf, [f])

  # verbose: prints the equivalent shell command (to stdout, as CRuby's own
  # fu_output_message does), noop: prints it and does nothing else. The paths
  # here are relative so the printed lines carry no pid.
  Dir.chdir(root) do
    FileUtils.mkdir_p("v/one", verbose: true)
    FileUtils.mkdir("v/two", verbose: true)
    FileUtils.rmdir("v/two", verbose: true)
    File.write("v/src.txt", "s")
    FileUtils.cp("v/src.txt", "v/copy.txt", verbose: true)
    FileUtils.cp_r("v/one", "v/one_copy", verbose: true)
    FileUtils.mv("v/copy.txt", "v/moved.txt", verbose: true)
    FileUtils.rm("v/moved.txt", verbose: true)
    FileUtils.rm_f("v/gone.txt", verbose: true)
    FileUtils.touch("v/t.txt", verbose: true)
    FileUtils.chmod(0o644, "v/t.txt", verbose: true)
    FileUtils.chmod_R(0o644, "v/one", verbose: true)
    FileUtils.ln_s("t.txt", "v/link", verbose: true)
    FileUtils.ln("v/t.txt", "v/hard", verbose: true)
    FileUtils.rm_r("v/one_copy", verbose: true)
    FileUtils.rm_rf(["v/one", "v/nope"], verbose: true)
    p Dir.exist?("v/one")

    # noop does not touch the filesystem, and still reports under verbose
    p FileUtils.mkdir_p("v/dry", verbose: true, noop: true)
    p Dir.exist?("v/dry")
    FileUtils.rm_rf("v", noop: true)
    p Dir.exist?("v")

    # cd reports the directory it enters, and the return under a block
    FileUtils.cd("v", verbose: true) { p File.basename(Dir.pwd) }
    p File.basename(Dir.pwd) == File.basename(root)
  end
ensure
  FileUtils.rm_rf(root) if defined?(FileUtils)
end
p Dir.exist?(root)
