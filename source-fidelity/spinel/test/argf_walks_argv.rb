# ARGF reads the program's ARGV as it stands when it needs the next file,
# taking each file off the front as it opens it, and a file that does not
# open raises Errno::ENOENT. Run with test/argf_input.txt twice, then a
# missing file. On da7617b5 the output differs from line 3 on: ARGV keeps
# its files, the missing file is skipped silently, and the file appended
# to ARGV is never read.
p ARGV.size
ARGV.shift
p ARGF.gets
p ARGV
p ARGF.filename
p ARGF.gets
p ARGF.gets
begin
  ARGF.gets
rescue Errno::ENOENT => e
  p e.message
end
p ARGV
ARGV << "test/argf_input.txt"
p ARGF.readlines
p ARGF.gets
