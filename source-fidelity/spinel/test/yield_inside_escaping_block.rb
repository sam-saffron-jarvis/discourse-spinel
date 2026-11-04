# A `yield` inside a block handed to a method that keeps a real &blk: the
# block becomes a first-class proc with its own C function, where the
# enclosing method's block is as out of reach as it is from a Thread body.
# The enclosing method is lowered the way a Thread-yielding one is (#3355):
# its block travels as a proc the lifted body can call. Before, the yield
# raised LocalJumpError; `packages/net`'s `Net::HTTP#request(req, &blk)` is
# this callee and campfire's link unfurler is this caller. (#4438)
class Http
  def request(req, &blk)
    res = "response:#{req}"
    blk.call(res) unless blk.nil?
    res
  end

  def start(host)
    yield self
  end
end

def outer(url)
  Http.new.request(url) do |response|
    yield response
  end
end

def nested(url)
  Http.new.start("h") do |http|
    http.request(url) do |response|
      if response.end_with?("skip")
        puts "redirect"
      else
        yield response
      end
    end
  end
  :done
end

def valued(url)
  Http.new.request(url) do |response|
    v = yield response
    puts "block answered #{v.inspect}"
  end
end

outer("x") { |r| puts r }
p nested("y") { |r| puts "got #{r}" }
p nested("skip") { |r| puts "never #{r}" }
valued("z") { |r| r.length }
outer("a") { |r| puts r.upcase }
