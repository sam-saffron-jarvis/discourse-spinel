# SystemCallError#errno answers the C errno of the Errno:: class the
# exception is an instance of, recovered from the class name at run time (the
# numbers differ by platform, and the class determines the number as in
# CRuby); the class constant's ::Errno is the same number; a plain
# SystemCallError has none, and the reader is not defined off the family
# (#4560, makenowjust).
e = (File.open("/nonexistent/x") rescue $!)
p e.errno == Errno::ENOENT::Errno
p e.errno.is_a?(Integer)
p Errno::ENOENT::Errno == Errno::EACCES::Errno
begin
  raise Errno::EACCES, "nope"
rescue SystemCallError => x
  p x.errno == Errno::EACCES::Errno
end
begin
  raise SystemCallError, "plain"
rescue SystemCallError => y
  p y.errno
end
errs = []
begin
  Dir.mkdir("/proc/no/such/dir")
rescue StandardError => z
  errs << z
end
p errs[0].errno == Errno::ENOENT::Errno
begin
  RuntimeError.new("x").errno
rescue NoMethodError => n
  puts n.message
end
