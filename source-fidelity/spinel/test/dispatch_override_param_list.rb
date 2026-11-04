# An override with its own parameter list, reached through the dispatch
# switch, binds the call's arguments by its own list (#4866).

class A1; def m(x, *rest) = x + rest.size; def run = m(3); end
class B1 < A1; def m(x) = x + 1; end

class A2; def m(x, y = 2) = x * y; def run = m(3); end
class B2 < A2; def m(x) = x + 1; end

class A3; def m(x, k: 1) = x * k; def run = m(3); end
class B3 < A3; def m(x) = x + 1; end

class A4; def m(x, &blk) = blk ? blk.call(x) : -x; def run = m(3) { |v| v * 10 }; end
class B4 < A4; def m(x) = x + 1; end

class A5; def m(x) = x; def run = m(3); end
class B5 < A5; def m(x, y = 1) = x + y; end
class C5 < A5; def m(x, *r) = x + r.size + 100; end
class D5 < A5; def m(x, k: 7) = x + k; end
class E5 < A5; def m(x, **kw) = x + kw.size + 200; end
class F5 < A5; def m(x, &blk) = blk ? 0 : x + 300; end

class A6; def m(x, y = 2) = x * y; def run = m(4); end
class B6 < A6; def m(x, y = 5) = x * y; end

class A7; def m(x) = x; def run = m(3, 4); end
class B7 < A7; def m(x, y = 1) = x + y; end

[A1, B1, A2, B2, A3, B3, A4, B4, A5, B5, C5, D5, E5, F5, A6, B6].each do |k|
  p k.new.run
end
p B2.new.m(3)
p B6.new.m(2)
begin
  A7.new.run
rescue ArgumentError => e
  puts "ArgumentError: #{e.message}"
end
p B7.new.run
