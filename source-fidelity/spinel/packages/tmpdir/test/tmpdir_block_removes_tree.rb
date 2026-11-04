# Dir.mktmpdir's block form removes the directory it made, and everything
# the block left inside it.
#
# Before this change the cleanup ran Dir.delete only when the directory was
# still empty, so the ordinary use, writing files into the directory and
# leaving, kept the directory and its files behind. Now the ensure removes
# the tree bottom-up, as CRuby's FileUtils.remove_entry does: a file, a
# nested directory, an empty directory, and a symlink, which is unlinked and
# never followed, so what it pointed at survives. The block's value is still
# the answer, and an exception from the block still carries through.
require "tmpdir"

# A file, a nested directory with a file, and an empty directory are all gone
path = nil
Dir.mktmpdir("spinel-tree-") do |d|
  path = d
  File.write("#{d}/payload", "data")
  Dir.mkdir("#{d}/nested")
  File.write("#{d}/nested/inner", "more")
  Dir.mkdir("#{d}/empty")
end
p Dir.exist?(path)

# The block's value is the answer
p(Dir.mktmpdir { |d| File.write("#{d}/x", "1"); 42 })

# A raise inside the block still removes the tree, and the exception carries through
path = nil
begin
  Dir.mktmpdir do |d|
    path = d
    File.write("#{d}/payload", "data")
    raise ArgumentError, "from the block"
  end
rescue ArgumentError => e
  p e.message
end
p Dir.exist?(path)

# A symlink inside the tree is unlinked, and what it pointed at survives
outside = Dir.mktmpdir
File.write("#{outside}/keep", "kept")
Dir.mkdir("#{outside}/keepdir")
File.write("#{outside}/keepdir/f", "kept too")
path = nil
Dir.mktmpdir do |d|
  path = d
  File.symlink("#{outside}/keep", "#{d}/link")
  File.symlink("#{outside}/keepdir", "#{d}/dirlink")
end
p Dir.exist?(path)
p File.read("#{outside}/keep")
p File.read("#{outside}/keepdir/f")
File.delete("#{outside}/keep")
File.delete("#{outside}/keepdir/f")
Dir.rmdir("#{outside}/keepdir")
Dir.rmdir(outside)
p Dir.exist?(outside)

# The non-block form still hands the directory to the caller
d = Dir.mktmpdir
p Dir.exist?(d)
Dir.rmdir(d)
