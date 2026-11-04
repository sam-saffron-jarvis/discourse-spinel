# Pathname#glob globbed "#{@path}/#{pattern}" verbatim, so a receiver of "."
# answered "./a/top.rs" where CRuby answers "a/top.rs": CRuby globs under the
# receiver and joins each match with `+`, which drops a leading "." and folds
# a trailing "/" or "/." on the receiver. Anything else, "./a" included, is
# kept as written (#4252).
require "pathname"

root = "/tmp/sp_pathname_glob_#{Process.pid}"
["", "/a", "/a/b"].each do |d|
  Dir.mkdir("#{root}#{d}") unless Dir.exist?("#{root}#{d}")
end
["a/top.rs", "a/b/mid.rs"].each { |f| File.write("#{root}/#{f}", "") }
Dir.chdir(root)

[".", "./", "./a", "a/", "a", "a/.", "./a/"].each do |base|
  pat = base.include?("a") ? "*.rs" : "a/*.rs"
  p [base, Pathname.new(base).glob(pat).map(&:to_s).sort]
end
p Pathname.new(".").glob("a/**/*.rs").map(&:to_s).sort
p Pathname.new("a").glob("**/*.rs").map(&:to_s).sort
p Pathname.new("nothing/here").glob("*").map(&:to_s)

Dir.chdir("/")
system("rm -rf #{root}")
