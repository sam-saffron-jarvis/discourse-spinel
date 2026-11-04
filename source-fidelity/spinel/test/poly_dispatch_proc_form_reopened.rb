# A `&blk` method defined by a package and reopened by the program: the
# reopening body is the one every call runs (last definition wins). The
# proc form a blockless poly-receiver call takes was cloned from the FIRST
# definition, and its parameter, which no call site binds, stayed untyped
# and reached the body as nil (#4502). The clone is taken from the
# definition the class resolves the name to, and its parameters are the
# poly slots the signature spells.
class Http
  def initialize(host)
    @host = host
  end

  def perform(req)
    "#{@host}:#{req.nil? ? "nil-req" : req.path}"
  end

  def request(req, &blk)
    res = perform(req)
    blk.call(res) unless blk.nil?
    res
  end
end

class Req
  attr_accessor :body

  def path
    "/hook"
  end
end

class Get
  def path
    "/get"
  end
end

# the program's reopen: a stub table in front of the transport
class Http
  def request(req, &blk)
    res = req.path == "/hook" ? "stubbed" : perform(req)
    blk.call(res) unless blk.nil?
    res
  end
end

def get(h)
  h.request(Get.new)
end

slots = { "h" => Http.new("example.test") }
puts slots["h"].request(Req.new.tap { |r| r.body = "x" })
puts get(Http.new("direct"))
