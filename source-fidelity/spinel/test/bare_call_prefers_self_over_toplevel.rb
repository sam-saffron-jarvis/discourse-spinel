# A bare call inside a method resolves to self first, as Ruby does: a
# top-level `def request` beside Http#request made the inline emitter take
# the free function for the `request(req)` inside Http#get, decline on its
# arity, and fall back to a call of sp_Http_request, a symbol the method
# never had because every other site inlined it (#4500). The analyzer had
# resolved it to self all along; the emitter now agrees.
def request = "top-level"

class Http
  def initialize(h) = @h = h
  def request(req, &blk)
    res = "#{@h}:#{req}"
    blk.call(res) unless blk.nil?
    res
  end
  def get(path)
    request("GET " + path)
  end
end

class Client
  def self.get(url) = Http.new("h").get(url)
end
puts Client.get("/")
puts request
