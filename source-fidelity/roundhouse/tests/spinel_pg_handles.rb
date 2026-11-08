# frozen_string_literal: true
require_relative "db_pg"

# Deliberately unreachable endpoint: PgConn must remain lazy throughout.
c = PgConn.new(PgConfig.new("postgres://unused@127.0.0.1:1/no_connect"))
raise "new connection has handles" unless c.open_count == 0
c.release_all
raise "empty release" unless c.open_count == 0
a = c.open_stmt("SELECT 1", false)
b = c.open_stmt("SELECT 2", false)
puts c.open_count
c.close_stmt(a)
puts c.slot_of(a)
c.close_stmt(a) # Double close must not enqueue the same slot twice.
d = c.open_stmt("SELECT 3", false)
puts c.slot_of(d)
puts c.slot_of(b)
raise "stale handle reused" unless d != a && c.slot_of(a) == -1
raise "live handle" unless c.stmt(d).handle == d && c.open_count == 2
c.release_all
puts c.open_count
raise "release kept a handle alive" unless c.slot_of(b) == -1 && c.slot_of(d) == -1
c.release_all
raise "repeated release" unless c.open_count == 0
x = c.open_stmt("SELECT 4", false)
y = c.open_stmt("SELECT 5", false)
raise "release did not reuse slots" unless c.slot_of(x) == 0 && c.slot_of(y) == 1
raise "release lost serial" unless x != a && x != d && y != b
raise "invalid handles" unless c.slot_of(0) == -1 && c.slot_of(-1) == -1
rejected = false
begin
  c.stmt(a)
rescue RuntimeError => e
  rejected = e.message.include?("unknown or finalized statement handle")
end
raise "stale statement was not refused" unless rejected
c.close_stmt(x)
c.close_stmt(y)
raise "final count" unless c.open_count == 0
puts "handle reuse, stale handles and repeated release: OK"
