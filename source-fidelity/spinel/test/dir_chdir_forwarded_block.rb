# `Dir.chdir(path, &block)`: the block a method forwards by name. Only a
# literal block reached the save/switch/restore splice, so a forwarded one
# was dropped -- the chdir became permanent and the block never ran, with
# nothing said. FileUtils.cd is written exactly this way.
require "tmpdir"

root = File.join(Dir.tmpdir, "sp_chdir_#{Process.pid}")
Dir.mkdir(root)
Dir.mkdir(File.join(root, "inner"))

def cd(dir, &block)
  Dir.chdir(dir, &block)
end

def cd_arg(dir, &block)
  Dir.chdir(dir) { |p| block.call(p) }
end

begin
  Dir.chdir(root) do
    p File.basename(Dir.pwd) == File.basename(root)
    p cd("inner") { File.basename(Dir.pwd) }
    p File.basename(Dir.pwd) == File.basename(root)

    # the forwarded block takes what Dir.chdir yields, the new directory
    p cd("inner") { |d| File.basename(d) }
    p cd_arg("inner") { |d| File.basename(d) }

    # a raising body still restores, and the rescue between the two chdir
    # splices catches it (test/ensure_reraises_into_enclosing_rescue.rb)
    begin
      cd("inner") { raise "boom" }
    rescue RuntimeError => e
      p e.message
    end
    p File.basename(Dir.pwd) == File.basename(root)

    # the blockless form still switches for good
    pr = proc { File.basename(Dir.pwd) }
    p cd("inner", &pr)
    p File.basename(Dir.pwd) == File.basename(root)
  end
  # A literal block's own parameter is the directory too: the splice dropped
  # the block's parameters, so it read as nil.
  Dir.chdir(root) do
    Dir.chdir("inner") { |d| p d }
    p File.basename(Dir.pwd) == File.basename(root)
    n = 0
    dirs = ["inner"]
    Dir.chdir(dirs[n]) { |d| p d == "inner" }
  end

ensure
  Dir.rmdir(File.join(root, "inner"))
  Dir.rmdir(root)
end
