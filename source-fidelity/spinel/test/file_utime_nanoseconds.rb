# File.utime / File.lutime took their times as a double, which drops a Time's
# nanoseconds: near 2^31 seconds a double has about 100ns of resolution, so
# the fraction was gone before utimes' microseconds could even carry it. The
# operands are a whole second and a nanosecond remainder now, straight into
# utimensat.
path = "spinel_utime_ns_#{Process.pid}.tmp"
link = "spinel_utime_ns_#{Process.pid}.lnk"
File.write(path, "x")
File.symlink(path, link)

nanos = 1789907379383895094
t = Time.at(nanos / 1_000_000_000, nanos % 1_000_000_000, :nanosecond)
p t.tv_sec
p t.nsec

p File.utime(t, t, path)
st = File.stat(path)
p st.mtime.tv_sec
p st.mtime.nsec
p st.atime.nsec

# the link's own times, which only an lstat sees
t2 = Time.at(1700000000, 123456789, :nanosecond)
p File.lutime(t2, t2, link)
p File.lstat(link).mtime.nsec
p File.stat(link).mtime.nsec == st.mtime.nsec   # the target is untouched

# a plain number is still seconds
p File.utime(1700000000, 1700000000, path)
p File.stat(path).mtime.tv_sec
p File.stat(path).mtime.nsec

File.unlink(link)
File.unlink(path)
