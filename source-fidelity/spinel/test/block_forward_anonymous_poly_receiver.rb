# An anonymous `&` forwarded to an iterator on a POLY receiver: the value of
# another block (`@mutex.synchronize { @items.dup }`, a snapshot handed out
# from under a lock) or of a widened method. The forward used to fall to the
# inline path, which spliced the caller's block into the forwarding method and
# ran it with the forwarder as self: `handle(item)` in the caller's block
# raised NoMethodError naming the registry (#4625). The forward is a yielding
# block now, one poly parameter per element, and self is the caller's.
class Registry
  def initialize
    @items = { a: 1, b: 2, c: 3 }
    @list = [3, 1, 2]
    @mutex = Mutex.new
  end

  def snap = @mutex.synchronize { @list.dup }
  def snaph = @mutex.synchronize { @items.dup }

  def each(&) = @mutex.synchronize { @items.values.dup }.each(&)
  def each_list(&) = snap.each(&)
  def each_pair(&) = snaph.each(&)
  def each_value(&) = snaph.each_value(&)
  def each_key(&) = snaph.each_key(&)
  def map(&) = snap.map(&)
  def hmap(&) = snaph.map(&)
  def select(&) = snap.select(&)
  def hselect(&) = snaph.select(&)
  def reject(&) = snap.reject(&)
  def find(&) = snap.find(&)
  def find_index(&) = snap.find_index(&)
  def any?(&) = snap.any?(&)
  def all?(&) = snap.all?(&)
  def none?(&) = snap.none?(&)
  def sort_by(&) = snap.sort_by(&)
  def min_by(&) = snap.min_by(&)
  def max_by(&) = snap.max_by(&)
  def group_by(&) = snap.group_by(&)
  def partition(&) = snap.partition(&)
  def count(&) = snap.count(&)
  def sum(&) = snap.sum(&)
  def flat_map(&) = snap.flat_map(&)
  def filter_map(&) = snap.filter_map(&)
  def take_while(&) = snap.take_while(&)
  def drop_while(&) = snap.drop_while(&)
end

class App
  def initialize
    @seen = []
    @n = 10
  end

  def run
    r = Registry.new
    r.each { |item| handle(item) }
    r.each_list { |item| handle(item) }
    r.each_pair { |k, v| handle([k, v]) }
    r.each_pair { |pair| handle(pair) }
    r.each_value { |v| handle(v) }
    r.each_key { |k| handle(k) }
    p @seen
    p r.map { |x| add(x) }
    p r.hmap { |k, v| [k, add(v)] }
    p r.select { |x| add(x) > 11 }
    p r.hselect { |k, v| add(v) > 11 }
    p r.reject { |x| add(x) > 11 }
    p r.find { |x| add(x) == 11 }
    p r.find_index { |x| add(x) == 11 }
    p r.any? { |x| add(x) == 11 }
    p r.all? { |x| add(x) == 11 }
    p r.none? { |x| add(x) == 99 }
    p r.sort_by { |x| -add(x) }
    p r.min_by { |x| -add(x) }
    p r.max_by { |x| -add(x) }
    p r.group_by { |x| add(x).odd? }
    p r.partition { |x| add(x).odd? }
    p r.count { |x| add(x).odd? }
    p r.sum { |x| add(x) }
    p r.flat_map { |x| [x, add(x)] }
    p r.filter_map { |x| add(x) if x > 1 }
    p r.take_while { |x| add(x) > 11 }
    p r.drop_while { |x| add(x) > 11 }
  end

  private

  def add(x) = x + @n

  def handle(item)
    @seen << item
  end
end

App.new.run
