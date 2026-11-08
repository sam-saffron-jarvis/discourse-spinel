# A boxed user protocol sharing Socket#connect_nonblock's name may accept
# exception: alone. The native socket arm must not count it as an address or
# emit an empty C expression for the default arm. No socket is opened here.
require "socket"
class KeywordOnlyChannel
  def connect_nonblock(exception: true)
    exception ? :connected : :wait_readable
  end
end
[KeywordOnlyChannel.new, nil].each do |channel|
  begin
    p channel.connect_nonblock(exception: false)
  rescue NoMethodError => error
    p error.class
  end
end
