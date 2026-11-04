# Dir.glob answered an empty list for every pattern form whose wildcard was not
# in the LAST component: the walk split at the last slash and opened the part
# before it as a literal directory, so "a/*/mid.rs" looked for a directory
# named "a/*". A character class found nothing either, because the matcher knew
# only * and ? where File.fnmatch (the system one) knows the whole language.
# Brace alternation was not expanded at all (#4252).
root = "/tmp/sp_glob_patterns_#{Process.pid}"
["", "/a", "/a/b", "/a/b/c", "/crates", "/crates/one", "/crates/one/src"].each do |d|
  Dir.mkdir("#{root}#{d}") unless Dir.exist?("#{root}#{d}")
end
["root.rs", "a/top.rs", "a/b/mid.rs", "a/b/c/deep.rs", "crates/one/src/lib.rs"].each do |f|
  File.write("#{root}/#{f}", "")
end
Dir.chdir(root)

def g(pat)
  Dir.glob(pat).sort
end

# a wildcard in a middle component, the reported shape
p g("a/*/mid.rs")
p g("a/?/mid.rs")
p g("a/*/*/deep.rs")

# a character class, which the system matcher has always understood
p g("a/[bx]/mid.rs")
p g("a/[!x]/mid.rs")
p g("root.[rs][st]")

# brace alternation, expanded before matching
p g("{a,crates}/*.rs")
p g("a/{b,zz}/mid.rs")
p g("{root,a/top}.rs")

# ** forms: trailing is one level, the separator form recurses, twice works
p g("a/**")
p g("a/**/*.rs")
p g("**/*.rs")
p g("**/src/**/*.rs")

# the last-component wildcard that already worked
p g("a/b/*.rs")
p g("*.rs")

# a pattern matching nothing is still empty
p g("a/*/nope.rs")
p g("{q,r}/*")

Dir.chdir("/")
["root.rs", "a/top.rs", "a/b/mid.rs", "a/b/c/deep.rs", "crates/one/src/lib.rs"].each do |f|
  File.delete("#{root}/#{f}")
end
["/crates/one/src", "/crates/one", "/crates", "/a/b/c", "/a/b", "/a", ""].each do |d|
  Dir.rmdir("#{root}#{d}")
end
