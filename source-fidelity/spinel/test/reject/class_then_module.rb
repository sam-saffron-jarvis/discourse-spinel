# CRuby refuses to LOAD this: "Thing is not a module (TypeError)". spinel built
# it, dropped the second declaration, and answered Class (#4309).
class Thing
end

module Thing
end

p Thing.class
