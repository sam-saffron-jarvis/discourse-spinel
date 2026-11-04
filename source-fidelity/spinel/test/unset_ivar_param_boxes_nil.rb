# An int ivar nothing has to assign before it is read starts as the nil
# sentinel, and a parameter bound from it hands the sentinel on. Boxing
# that parameter made a truthy Integer of nil, so `page && page > 1` raised
# NoMethodError for nil > 1 instead of answering "first" (#5085).
class Ctl
  def all
    @page = 2
    show
  end

  def unread
    show
  end

  def show
    View.page(@page)
  end
end

module View
  def self.page(page)
    io = +""
    page_into(io, page)
    io
  end

  def self.page_into(io, page)
    io << (page && page > 1 ? "prev" : "first")
  end
end

puts Ctl.new.all
puts Ctl.new.unread
puts View.page_into(+"", 2.5)

# through a second parameter, and handed over directly
class Deep
  def show = A.one(@n)
end
module A
  def self.one(n) = two(n)
  def self.two(n) = three(n)
  def self.three(n) = n ? "n=#{n}" : "no n"
end
puts Deep.new.show
puts A.three(nil)
puts View.page_into(+"", nil)
