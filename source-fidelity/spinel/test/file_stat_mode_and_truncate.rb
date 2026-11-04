# A File::Stat handle records which of stat(2) and lstat(2) made it, and every
# accessor is supposed to read the struct that one selects. The type
# predicates and the time accessors went through the PATH helpers instead --
# sp_file_symlink(path) always lstats, sp_file_mtime(path) always stats -- so
# `File.stat(link).symlink?` answered true and `File.lstat(link)` reported the
# TARGET's times. File#truncate and File.lutime had no emitter at all.
path = "spinel_stat_mode_#{Process.pid}.tmp"
link = "spinel_stat_mode_#{Process.pid}.lnk"
File.write(path, "hello world")
File.symlink(path, link)

p File.lstat(link).symlink?     # the link itself
p File.stat(link).symlink?      # ...followed: a regular file
p File.lstat(link).file?
p File.stat(link).file?
p File.lstat(link).directory?
p File.stat(path).size

# lutime touches the LINK's times, so an lstat sees them and a stat does not
p File.lutime(Time.now - 100, Time.now - 100, link)
p File.lstat(link).mtime < File.stat(path).mtime
p File.stat(link).mtime == File.stat(path).mtime

# File#truncate cuts the open handle
f = File.open(path, "r+")
p f.truncate(5)
f.close
p File.read(path)
p File.stat(path).size

File.unlink(link)
File.unlink(path)
