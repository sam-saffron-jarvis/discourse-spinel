# Ruby's own ipaddr — see `project::IPADDR_STDLIB`.
# The port at runtime/ruby/ipaddr.rb exists for the targets
# that have no stdlib to reach for; this tree has one, and
# defining a second IPAddr beside it is a superclass mismatch
# at require time.
require "ipaddr"

class IPAddr
  # The port's representation, answered by the stdlib's: 4 octets for
  # IPv4, 16 for IPv6, masked to the prefix.
  def octets
    hton.bytes
  end unless method_defined?(:octets)
end
