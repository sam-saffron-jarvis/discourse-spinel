# CRuby refuses to LOAD this: "superclass mismatch for class Thing
# (TypeError)". spinel built it, kept the first superclass, and answered A
# (#4309).
class A
end

class B
end

class Thing < A
end

class Thing < B
end

p Thing.superclass
