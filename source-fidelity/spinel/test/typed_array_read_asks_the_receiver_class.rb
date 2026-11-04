# Whether a `.to_a` reads storage something else holds (#4412's copy
# refusal) is a question about the RECEIVER's class, not about every
# class in the program that spells a method by that name. `(1..max).to_a`
# makes a fresh array; it does not become a read of `@rows` because a
# `Result#to_a` answering `@rows` exists somewhere else. The name-only
# scan refused this program -- lobsters' pagination helper, beside the
# ActiveRecord::Result stand-in every transpiled tree carries.
class Result
  def initialize(rows)
    @rows = rows
  end

  def to_a
    @rows
  end
end

def pages(max, cur)
  return (1..max).to_a if max <= 3

  pages = (cur - 1..cur + 1).to_a
  pages.unshift "..." if pages[0] > 1
  pages
end

r = Result.new([1, 2])
a = r.to_a
a << 3
p r.to_a.equal?(a)   # the reader still aliases: true
p pages(2, 1)
p pages(9, 5)
