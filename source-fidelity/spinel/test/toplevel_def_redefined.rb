# a redefined top-level method is its last definition
def tw(&b) = [:first]
def tw(a)
  a.each { |x| yield x }
  [:second]
end
p tw([1]) { |x| x }

def pick = :one
def pick = :two
p pick

def ar(a) = [:first, a]
def ar(a, b = 2) = [:second, a, b]
p ar(1)
p ar(1, 3)

def typed(x) = x + 1
def typed(x) = "#{x}!"
p typed(4)

def caller_of = pick
p caller_of

class C
  def pick = :c_one
  def pick = :c_two
  def via_top = ar(9)
end
p C.new.pick
p C.new.via_top

# a call between two definitions reaches the one defined so far; a method
# body runs later, and reaches the last
def step = 1
def later = step
p step
[1].each { p step }
def step = 2
p step
p later
def q? = :q1
p q?
def q? = :q2
p q?
