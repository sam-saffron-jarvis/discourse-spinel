# A method reached through a receiver that settled on NO type is a runtime
# dispatch: the argument arrives boxed and the arm converts it to whatever the
# parameter says. The parameter was left to the OTHER call sites, so a String
# was taken apart as the Integer those had settled on -- the stored comparator
# then ran the String block over Integers (#4294).
class Chain
  attr_reader :value, :rest, :size

  def self.empty(&comparator) = new(nil, nil, 0, comparator || ->(a, b) { a <=> b })

  def self.from(items, &comparator)
    items.reduce(empty(&comparator)) { |chain, item| chain.push(item) }
  end

  def initialize(value, rest, size, comparator)
    @value = value
    @rest = rest
    @size = size
    @comparator = comparator
  end

  def empty? = @size.zero?

  def push(item)
    return Chain.new(item, self, @size + 1, @comparator) if empty? || @comparator.call(item, @value) <= 0

    Chain.new(@value, @rest.push(item), @size + 1, @comparator)
  end

  def drain
    out = []
    chain = self
    until chain.empty?
      out << chain.value
      chain = chain.rest
    end
    out
  end
end

chains = [Chain.empty]
[23, 4, 17].each { |n| chains << chains.last.push(n) }
p chains.last.drain
p Chain.from([23, 17]).drain
p Chain.from(%w[pear fig banana]) { |a, b| a.length <=> b.length }.drain
