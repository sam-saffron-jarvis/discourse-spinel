# An if whose other arm is not a container gets its empty [] arm boxed,
# and one whose other arm only raises answers the empty literal (#4938)
class Rel
  def initialize(ids) = @ids = ids
  def size = @ids.size
end

class Ctl
  def initialize(user) = @user = user
  def show
    @read = if @user
      Rel.new([1, 2])
    else
      []
    end
    @read.size
  end
end

p Ctl.new(true).show
p Ctl.new(nil).show

class Parser
end

class Search
  def initialize(q) = @q = q
  def run
    @tree = if !@q.empty?
      Parser.new.parse(@q)
    else
      []
    end
    @tree
  end
end

p Search.new("").run
begin; Search.new("x").run; rescue NoMethodError; p :raised; end
