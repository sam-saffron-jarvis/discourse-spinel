# A pattern whose first byte is not ASCII: the compiler's first-byte bitmap
# is 128 bits, and a leading multibyte literal (one RE_CHAR per UTF-8 byte,
# 0xC3.. 0xF0..) indexed past it on re_compile's stack. campfire's emitted
# runtime carries such a pattern and its ASAN build died at startup.
words = "café crème brûlée élan"
p words.scan(/é/)
p words =~ /élan/
p words.gsub(/è|û/, "_")
p "日本語のテキスト" =~ /語の/
p "日本語のテキスト".scan(/[語テ]/)
p ("ünïcödé" =~ /ü/)
p "aé".match?(/^é/)
p "éa".match?(/^é/)
