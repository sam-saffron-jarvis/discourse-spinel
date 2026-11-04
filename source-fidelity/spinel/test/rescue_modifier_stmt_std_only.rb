# A bare `rescue` -- including the modifier form -- catches StandardError and
# its descendants only. #3725 put that guard on the modifier used as an rvalue
# and its statement twin kept catching everything, so `foo rescue handler`
# swallowed an Exception, a ScriptError and a SystemExit. The last one is the
# loud case: `exit 3` behind a statement-position modifier ended the program
# with status 0 and carried on.

def std;  raise "std";                        end
def exc;  raise Exception, "raw";             end
def scr;  raise NotImplementedError, "np";    end

# StandardError: caught, as before
std rescue puts("caught std")
puts "after std"

# Exception and ScriptError: not caught, so they reach an outer handler
begin
  exc rescue puts("MUST NOT PRINT")
rescue Exception => e
  p ["outer", e.class.to_s, e.message]
end

begin
  scr rescue puts("MUST NOT PRINT")
rescue ScriptError => e
  p ["outer", e.class.to_s]
end

# a rescue modifier still catches a StandardError raised in a called method
def wrapped
  (raise ArgumentError, "bad") rescue "recovered"
end
p wrapped

# the rvalue form was already right; pinned so the two stay together
begin
  x = (exc rescue "MUST NOT REACH")
  p x
rescue Exception => e
  p ["rvalue also declined", e.class.to_s]
end

# and a SystemExit is not swallowed either: this one is caught by an outer
# handler rather than ending the program, which is what proves it got past
# the modifier
begin
  (exit 3) rescue puts("MUST NOT PRINT")
rescue SystemExit => e
  p ["systemexit reached the outer handler", e.status]
end
