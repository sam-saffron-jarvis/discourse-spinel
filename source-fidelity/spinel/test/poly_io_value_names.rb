# The poly-IO arm emits these names, but the analyze twin typed only some of
# them. A name it did not type read as valueless, so the value the arm had
# already produced was DISCARDED: `@fds[k].path` through a method answered nil
# while the handle knew its path perfectly well. The shape needs the value to
# cross a method boundary, which is why a bare `io.path` looked fine.
class T
  def initialize = @fds = {}
  def add(k, hp, mode) = @fds[k] = File.open(hp, mode, 0o644)
  def path_of(k) = @fds[k].path
  def to_path_of(k) = @fds[k].to_path
  def lines_of(k) = @fds[k].readlines
  def rewind_of(k) = @fds[k].rewind
  def read_of(k) = @fds[k].read
  def close(k) = @fds[k].close
end
path = "spinel_poly_io_val_#{Process.pid}.tmp"
File.write(path, "hello world\n")
t = T.new
t.add(3, path, File::RDONLY)
p t.path_of(3) == path      # the value, not nil: the path is the file's
p t.to_path_of(3) == path
p t.lines_of(3)
p t.rewind_of(3)
p t.read_of(3)
t.close(3)
p File.read(path)
File.unlink(path)
