# A yielding method called from two sites, one block answering a value and
# the other answering nothing.
#
# The method is inlined per call site, and which type each site's slot takes
# comes from a scan that stops at the FIRST site unless the sites are found to
# diverge. That check asked whether the union of the sites was poly -- and a
# nil site has a union with anything: nil joined to a String is a nullable
# String. So the two read as agreeing, the first site's type was handed to
# every site, and with the nil site first the other site's value was typed
# from it and dropped. Nothing raised; the call simply answered nil.
def with_path(&block)
  p1 = "a.img"
  yield p1
end

def assert_ok(v)
  return if v
  raise "bad"
end

def find(path) = path.end_with?(".img") ? "Heif" : nil

# the nil site comes first, which is what settled the type
def blocked = with_path { |p| assert_ok(p) }
def loader  = with_path { |p| find(p) }

blocked
p loader

# the same through an ensure frame, where the value leaves in a slot of its
# own: `b` answers nothing, `a` a String
def with_f(&block)
  f = "a.img"
  begin
    yield f
  ensure
    f.size
  end
end
def check(v)
  return if v == "a.img"
  raise "bad"
end
def ea = with_f { |f| find(f) }
def eb = with_f { |f| check(f) }
eb
p ea

# two sites that agree keep their concrete type
def twice(&block) = yield(2)
p twice { |n| n * 3 }
p twice { |n| n + 1 }
