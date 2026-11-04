# A `&blk` method reached blockless through a poly receiver calls its proc
# form, and the arm spells each argument for the proc form's own parameter
# (#4492). A parameter inference left unknown is spelled sp_RbVal in the
# signature, so the argument has to arrive boxed there too: campfire's
# `http.request(Net::HTTP::Post.new(...).tap { ... })` handed the proc
# form a raw sp_Post * and did not build (#4499).
class Post
  attr_accessor :body
  def initialize(uri) = @uri = uri
  def path = @uri
end
class Get
  def initialize(uri) = @uri = uri
  def path = @uri
end
class Http
  def initialize(host) = @host = host
  def request(req, &blk)
    res = "#{@host}#{req.path}:#{req.is_a?(Post) ? req.body : "-"}"
    blk.call(res) unless blk.nil?
    res
  end
end
class Other
  def request = "other"
end
class Hook
  def initialize(h) = @slots = h
  def post(payload)
    http = @slots["h"]
    http.request Post.new("/p").tap { |r| r.body = payload }
  end
  def get
    http = @slots["h"]
    http.request(Get.new("/g"))
  end
end
hk = Hook.new({ "h" => Http.new("example"), "o" => Other.new })
puts hk.post("data")
puts hk.get
h = Http.new("x")
puts h.request(Get.new("/z")) { |r| puts "cb #{r}" }
