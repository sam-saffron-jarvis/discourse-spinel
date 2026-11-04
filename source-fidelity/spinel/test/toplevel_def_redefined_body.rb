# A redefined top-level method (#4971 follow-up): the earlier body calls
# itself while it runs, an alias written between the two names the earlier
# body, and the private name given to the earlier def avoids a name the
# program already defines.
def fact(n) = n <= 1 ? 1 : n * fact(n - 1)
p fact(5)
def fact(n) = 0
p fact(5)

def h = 1
alias saved h
def h = 2
p saved
p h

def g__redef1 = :user_named
def g = :first
p g
def g = :second
p g
p g__redef1
