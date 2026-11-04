# A pointer-backed handle IS nil when it is NULL in this backend, which is what
# `nil?` answers. `== nil` reached the "a value of another static kind is never
# equal" arm and folded to false, so a slot holding nil answered false to
# `== nil` and false to `!= nil` at the same time.
r, w = IO.pipe
x = r.wait_readable(0)          # an empty pipe: a handle-typed slot holding nil
p x.nil?
p((x == nil))
p((x != nil))
p((nil == x))
p((x == r))
p((x == x))

f = File.open("/etc/hosts")
p((f == nil))
p((f != nil))
p((f == f))
p((f == r))

d = Dir.open("/tmp")
p((d == nil))
p((d != nil))
p((d == d))

# the same through eql? and equal?, which share the arm
p f.eql?(nil)
p f.equal?(nil)
p x.eql?(nil)

r.close
w.close
f.close
d.close
