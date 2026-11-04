# File.open / File.new with a mode the analysis cannot classify -- a value read
# out of a mixed container, or a flags word computed into a boxed slot -- is
# decided at run time, as CRuby decides it (#to_int before #to_str). Assumed to
# be a mode string, an Integer flag word reached the String coercion and raised
# "no implicit conversion of Integer into String".
# cwd-relative: Windows MinGW has no /tmp (see feedback_windows_tmp_path)
path = "spinel_poly_mode_#{Process.pid}.tmp"
File.write(path, "hello")
h = { int: File::RDONLY, str: "r", none: nil }
m = h[:int]
io = File.open(path, m);            p io.read; io.close
io = File.open(path, m, 0o644);     p io.read; io.close
io = File.new(path, m);             p io.read; io.close
p(File.open(path, m) { |f| f.read })
io = File.open(path, h[:str]);      p io.read; io.close    # a boxed mode STRING still works
io = File.open(path, File::RDONLY); p io.read; io.close    # the inline constant is unchanged
mode = File::RDONLY
io = File.open(path, mode);         p io.read; io.close    # and so is a typed local
# a write mode through the same boxed slot really writes
w = { m: File::WRONLY | File::CREAT | File::TRUNC }
io = File.open(path, w[:m], 0o600); io.write("bye"); io.close
p File.read(path)
File.unlink(path)
