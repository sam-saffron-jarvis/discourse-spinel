# A request header value that carries a carriage return or a line feed is
# refused with ArgumentError, the way CRuby's Net::HTTPHeader refuses it,
# instead of being stored and written between the header name and its CRLF
# on the wire, where the text after the break becomes a header of its own.
# Every line here is diffed against CRuby's own net/http; nothing touches the
# network. The two entry points have different messages in CRuby and both
# are pinned: `[]=` names no header, the initheader form names the header and
# inspects the value, and it strips the value first, so a trailing newline
# there is whitespace, not an injection.
require "net/http"

def try(label)
  yield
  puts "#{label}: accepted"
rescue ArgumentError => e
  puts "#{label}: ArgumentError: #{e.message}"
end

req = Net::HTTP::Get.new("/")

try("cr") { req["X-Note"] = "hello\rX-Injected: yes" }
try("lf") { req["X-Note"] = "hello\nX-Injected: yes" }
try("crlf") { req["X-Note"] = "hello\r\nX-Injected: yes" }
try("trailing lf") { req["X-Note"] = "hello\n" }
try("array element") { req["X-Multi"] = ["one", "two\nX-Injected: yes"] }
try("array element cr") { req["X-Multi"] = ["one\r", "two"] }
puts "after refusals key? #{req.key?("X-Note")} #{req.key?("X-Multi")}"

try("plain") { req["X-Note"] = "hello" }
try("spaces kept") { req["X-Pad"] = " padded " }
try("array") { req["X-Multi"] = ["one", "two"] }
try("integer") { req["X-Num"] = 7 }
puts "stored #{req["X-Note"].inspect} #{req["X-Pad"].inspect} #{req["X-Multi"].inspect} #{req["X-Num"].inspect}"

try("initheader lf") { Net::HTTP::Get.new("/", "X-Note" => "hello\nX-Injected: yes") }
try("initheader cr") { Net::HTTP::Post.new("/", "X-Note" => "a\rb") }
try("initheader crlf") { Net::HTTP::Get.new("/", "Content-Type" => "text/plain\r\nX-Injected: yes") }
try("initheader second key") { Net::HTTP::Get.new("/", "X-A" => "ok", "X-B" => "bad\n") }
# CRuby strips the value before it checks it and so raises NoMethodError for an
# Array there; this package joins the Array and refuses the break with
# ArgumentError. Both refuse, which is what a caller can rely on.
begin
  Net::HTTP::Get.new("/", "X-Multi" => ["one", "two\nX-Injected: yes"])
  puts "initheader array element: accepted"
rescue StandardError
  puts "initheader array element: refused"
end

r = Net::HTTP::Get.new("/", "X-Note" => "hello\n", "X-Pad" => " padded ")
puts "initheader stripped #{r["X-Note"].inspect} #{r["X-Pad"].inspect}"
r = Net::HTTP::Post.new("/", "Content-Type" => "text/plain")
puts "initheader plain #{r["Content-Type"].inspect}"

# Appending to what `[]` answers does not raise, and reads back the same.
q = Net::HTTP::Get.new("/")
q["Y"] = "vv"
q["Y"] << "!"
puts "append to stored #{q["Y"].inspect}"
