# A keyword the callee does not declare.
#
# An ordinary call raises ArgumentError before the body runs, as CRuby does.
# A call that is INLINED -- which is what happens to a method that yields,
# since there is no function to call -- ran with the keyword simply gone. The
# two paths bind parameters in opposite directions: the ordinary one walks the
# call's arguments, the inline one walks the callee's PARAMETERS looking for
# keys, so a key that names no parameter was never looked at and never
# complained about.
#
# Where it bit: `Net::HTTP.start(host, port, ipaddr: ip, use_ssl: ...)` against
# a `self.start` that does not declare `ipaddr:`. The keyword carries a
# DNS-rebinding pin, and it was discarded in silence (#4419).
#
# The rule now lives in one function that both paths call, because a rule in
# two places is a rule that drifts -- and these two had already drifted.
class Client
  def self.open(host, port = 80, use_ssl: false)
    yield "#{host}:#{port} ssl=#{use_ssl}"
  end

  # the same signature without a yield, so it is called rather than inlined
  def self.plain(host, use_ssl: false)
    "#{host} ssl=#{use_ssl}"
  end
end

# declared keywords still bind, and the optional positional still defaults
Client.open("h", 443, use_ssl: true) { |c| puts c }
Client.open("h", use_ssl: true) { |c| puts c }
Client.open("h") { |c| puts c }
puts Client.plain("h", use_ssl: true)
puts Client.plain("h")

# an undeclared one raises on both paths, with CRuby's message
begin
  Client.open("h", 443, ipaddr: "1.2.3.4", use_ssl: true) { |c| puts c }
  puts "NOT REACHED"
rescue ArgumentError => e
  puts "inlined: #{e.message}"
end

begin
  Client.plain("h", ipaddr: "1.2.3.4", use_ssl: true)
  puts "NOT REACHED"
rescue ArgumentError => e
  puts "called: #{e.message}"
end

# A hash argument that names no keyword parameter at all is a positional Hash,
# not a keyword list, so its keys are data and must not be judged.
def takes_hash(h)
  h.size
end
puts takes_hash(alpha: 1, beta: 2)
