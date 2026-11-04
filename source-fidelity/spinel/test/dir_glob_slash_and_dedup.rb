# Three ways the component walk still differed from CRuby (#4258):
#   - a pattern ending in a separator names DIRECTORIES and keeps the
#     separator on the answer; the separator was dropped as an empty
#     component, so a regular file answered as if it were a directory;
#   - two or more recursive components with anything after them found each
#     path once per way of dividing the levels between them, where CRuby
#     answers a path once;
#   - the recursive form followed a symlinked directory, where CRuby does not
#     (which is also what stops a link back up the tree looping).
root = "/tmp/sp_glob_slash_#{Process.pid}"
["", "/a", "/a/b", "/a/b/c"].each do |d|
  Dir.mkdir("#{root}#{d}") unless Dir.exist?("#{root}#{d}")
end
["a/t.rs", "a/b/m.rs", "a/b/c/l.rs"].each { |f| File.write("#{root}/#{f}", "") }
File.symlink("#{root}/a/b", "#{root}/a/link") unless File.symlink?("#{root}/a/link")
Dir.chdir(root)

def g(pat)
  Dir.glob(pat).sort
end

# a trailing separator selects directories, and keeps the separator
p g("a/t.rs")
p g("a/t.rs/")
p g("a/")
p g("a/b/")
p g("*/")
p g("a/*/")

# repeated recursive components answer each path once
p g("a/**/*.rs")
p g("a/**/**/*.rs")
p g("**/**/m.rs")
p g("**/**/**/*.rs")

# the recursive form does not follow a symlinked directory; the plain one
# still lists it
p g("**/*.rs")
p g("a/*")
p g("**/")

Dir.chdir("/")
File.delete("#{root}/a/link")
["a/t.rs", "a/b/m.rs", "a/b/c/l.rs"].each { |f| File.delete("#{root}/#{f}") }
["/a/b/c", "/a/b", "/a", ""].each { |d| Dir.rmdir("#{root}#{d}") }
