# connect_nonblock, and sync_close, without a certificate and without a
# network peer that speaks TLS.
#
# The shape is CRuby's:
#
#   begin
#     ssl.connect_nonblock
#   rescue IO::WaitReadable
#     IO.select([sock]); retry
#   end
#
# and the discriminator is that the peer here NEVER answers. A handshake is
# the first thing on a connection, so the ClientHello goes out and the reply
# never comes: the call has to return :wait_readable rather than sit in the
# kernel, and a second call has to RESUME the same half-finished handshake
# rather than start a new one. A blocking connect wrapped in a rescue cannot
# produce either answer -- it has nothing to raise, and it never returns.
require "openssl"
require "socket"

srv = TCPServer.new("127.0.0.1", 0)
cli = TCPSocket.new("127.0.0.1", srv.addr[1])
peer = srv.accept                        # accepted, and silent from here on

ssl = OpenSSL::SSL::SSLSocket.new(cli)
ssl.hostname = "127.0.0.1"

p ssl.connect_nonblock(exception: false)
p ssl.connect_nonblock(exception: false)

begin
  ssl.connect_nonblock
  puts "no raise"
rescue OpenSSL::SSL::SSLErrorWaitReadable => e
  puts "raised #{e.class}"
end

# the wait classes catch as IO::WaitReadable, which is what the retry idiom
# above actually rescues
begin
  ssl.connect_nonblock
rescue IO::WaitReadable
  puts "caught as IO::WaitReadable"
end

# sync_close: the handle is live (the handshake is unfinished, not absent),
# so sysclose releases it and takes the socket with it. The unset default is
# not pinned: CRuby's reads back nil and this package's false, since a
# statically typed ivar has no third state to start in.
ssl.sync_close = true
ssl.sysclose
p cli.closed?

peer.close
srv.close
puts "end"
