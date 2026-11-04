# IO.pipe's WRITE end is sync in CRuby: a write reaches the descriptor at once,
# so a reader on the other end -- or an IO.select on it -- sees the bytes
# without a flush. Here #sync answered from the socket flag alone, so the write
# end reported false and its bytes sat in stdio (#4263).
r, w = IO.pipe
p w.sync
w.write "x"
p IO.select([r], nil, nil, 0).nil?
p r.read(1)

# the non-destructured spelling answers the same way
pair = IO.pipe
r2 = pair[0]
w2 = pair[1]
p w2.sync
w2.write "y"
p IO.select([r2], nil, nil, 0).nil?
p r2.read(1)

# a file is buffered, and sync= is remembered per handle
path = "/tmp/sp_pipe_sync_#{Process.pid}"
f = File.open(path, "w")
p f.sync
f.sync = true
p f.sync
f.sync = false
p f.sync
f.close
File.delete(path)

r.close
w.close
r2.close
w2.close
puts "ok"
