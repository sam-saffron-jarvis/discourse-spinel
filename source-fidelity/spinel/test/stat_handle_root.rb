# A File::Stat handle fills its own path with a fresh heap string, and the
# sprintf that builds that string can collect. Nothing rooted the handle
# across it, so the collector swept the object the constructor was still
# filling in and the caller got a freed one back. Each loop below allocates a
# big string first, so the string heap is over its trigger when the
# constructor runs, and small objects afterwards, so the freed block is handed
# out again before the handle is read. On master every section faults, with
# and without SPINEL_GC_STRESS=1.
path = "/tmp/sp_stat_root_#{Process.pid}"
link = "/tmp/sp_stat_root_link_#{Process.pid}"
File.write(path, "hello")
File.symlink(path, link) rescue nil

def churn
  junk = []
  j = 0
  while j < 20
    junk << [j, j, j]
    j += 1
  end
  junk.length
end

# File.stat: the handle still compares equal to one taken before the loop, and
# still answers for the file it was made from.
sa = File.stat(path)
bad_eq = 0
bad_size = 0
n = 0
while n < 300
  big = "x" * 200000
  sb = File.stat(path)
  churn
  bad_eq += 1 unless sa == sb
  bad_size += 1 unless sb.size == 5 && big.length == 200000
  n += 1
end
p [bad_eq, bad_size]

# File.lstat: the same constructor, describing the link itself.
la = File.lstat(link)
bad_link = 0
bad_ftype = 0
n = 0
while n < 300
  big = "y" * 200000
  lb = File.lstat(link)
  churn
  bad_link += 1 unless la == lb
  bad_ftype += 1 unless lb.ftype == "link" && big.length == 200000
  n += 1
end
p [bad_link, bad_ftype]

# IO#stat on a handle that carries a path goes through the same constructor.
bad_io = 0
n = 0
while n < 300
  big = "z" * 200000
  File.open(path) do |f|
    fs = f.stat
    churn
    bad_io += 1 unless fs.size == 5 && big.length == 200000
  end
  n += 1
end
p bad_io

File.delete(link)
File.delete(path)
