# Two rescue clauses binding the same name intern to one local, so the slot
# lands on the plain exception type and a call naming a method only the user
# class owns had no route at all. A read inside an arm still knows which class
# it is: the arm names it (#4343).
class Refused < StandardError
  attr_reader :said

  def initialize(said)
    super(said)
    @said = said
  end
end

class Misplaced < Refused
  attr_reader :line

  def initialize(line)
    super("misplaced")
    @line = line
  end
end

def two_clauses(x)
  raise x
rescue Misplaced => e
  puts "M #{e.line} #{e.said} #{e.message}"
rescue Refused => e
  puts "R #{e.said} #{e.message}"
end

two_clauses(Misplaced.new(9))
two_clauses(Refused.new("plain"))

# the method is the shared ancestor's, and neither arm names that ancestor
class Base < StandardError
  def kind = "base"
end

class Left < Base; end
class Right < Base; end

def inherited(x)
  raise x
rescue Left => e
  puts "L #{e.kind}"
rescue Right => e
  puts "R #{e.kind}"
end

inherited(Left.new("x"))
inherited(Right.new("y"))

# one clause is enough to lose it too, when the method is inherited
def one_clause
  raise Left.new("z")
rescue Left => e
  puts "one #{e.kind}"
end

one_clause

# the binding outlives the clause, and reads there keep the exception surface
def after
  begin
    raise Misplaced.new(3)
  rescue Misplaced => e
    puts "in #{e.line}"
  rescue Refused => e
    puts "in #{e.said}"
  end
  p e.class
  puts e.message
end

after
