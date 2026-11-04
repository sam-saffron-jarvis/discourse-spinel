# `Q` is UNSIGNED: a byte pattern with the top bit set is a Bignum in Ruby,
# not the negative number a signed read answers. And neither 64-bit
# directive's full range fits an sp_int slot -- Q past 2**63-1 is a Bignum,
# q's INT64_MIN is the value that slot spells as nil -- so unpack1 keeps
# them boxed rather than typing them int.
p "\x00\x00\x00\x00\x00\x00\x00\x80".b.unpack1("Q<")
p "\xff\xff\xff\xff\xff\xff\xff\xff".b.unpack1("Q<")
p "\x00\x00\x00\x00\x00\x00\x00\x80".b.unpack("Q<")
p "\x80\x00\x00\x00\x00\x00\x00\x00".b.unpack1("Q>")
p "\xff\xff\xff\xff\xff\xff\xff\xff".b.unpack("Q>")
p "\xff\xff\xff\xff\xff\xff\xff\x7f".b.unpack1("Q<")   # 2**63-1: still an int
p "\x00\x00\x00\x00\x00\x00\x00\x00".b.unpack1("Q<")
p "\x01\x00\x00\x00\x00\x00\x00\x00".b.unpack1("Q<")
# the signed twin: INT64_MIN is a value, not a nil
p "\x00\x00\x00\x00\x00\x00\x00\x80".b.unpack1("q<")
p "\xff\xff\xff\xff\xff\xff\xff\xff".b.unpack1("q<")
p "\xff\xff\xff\xff\xff\xff\xff\x7f".b.unpack1("q<")
p "\x00\x00\x00\x00\x00\x00\x00\x80".b.unpack("q<")
# the float-bits round trip every negative double takes
p [-0.0].pack("E").unpack1("Q<")
p [-1.5].pack("E").unpack1("Q<")
p [1.5].pack("E").unpack1("Q<")
p [2**64 - 1].pack("Q<").unpack1("Q<")
p [2**63].pack("Q<").unpack1("Q<")
p ["\x00\x00\x00\x00\x00\x00\x00\x80".b.unpack1("Q<") + 1]
