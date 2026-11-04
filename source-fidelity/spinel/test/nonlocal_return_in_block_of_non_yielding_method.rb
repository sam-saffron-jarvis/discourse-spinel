# A block handed to a method that neither yields nor takes a &block never
# runs. `fetch_content_type`'s only value is the `return` inside such a
# block (the yield that would reach it sits in a block `Http#request`
# never runs), and its body ends in a raise. The block's param carried no
# evidence and stayed untyped, the return typed nothing, and the method
# came out void -- so the caller's `!=` was refused. (#4431)
class Resp
  def initialize(h); @h = h; end
  def [](k); @h[k]; end
end

class Http
  def self.start(host, port, ipaddr: nil, use_ssl: false)
    yield new
  end
  def request(req)
    Resp.new({ "Content-Type" => "image/png" })
  end
end

class Fetch
  MAX_REDIRECTS = 10

  def fetch_content_type(url, ip = "127.0.0.1")
    request(url, "HEAD", ip: ip) do |response| return response["Content-Type"] end
  end

  def request(url, request_class, ip:)
    MAX_REDIRECTS.times do
      Http.start("h", 80, ipaddr: ip, use_ssl: false) do |http|
        http.request request_class do |response|
          if response.nil?
            url, ip = resolve_redirect(response["location"])
          else
            yield response
          end
        end
      end
    end

    raise "TooManyRedirects"
  end

  def resolve_redirect(location)
    [ location, "127.0.0.1" ]
  end
end

f = Fetch.new
begin
  raise "assert_equal failed" if "image/png" != f.fetch_content_type("u")
rescue RuntimeError => e
  puts e.message
end
