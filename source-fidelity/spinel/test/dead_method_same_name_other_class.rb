# Codegen reachability is by NAME, so a live `sign_in` on one class pulls an
# unrelated class's DEAD `sign_in` into codegen -- and the `post` inside that
# one has no answer in its own class's chain. Refusing to build made a
# per-file result depend on what else was linked in (#4340); CRuby runs it,
# because the dead body never executes.
module RequestDispatch
  def post(path, params: {})
    puts "post " + path + " " + params[:u].to_s
  end
end

class TestBase
end

class IntegrationTest < TestBase
  include RequestDispatch
end

class ModelTest < TestBase
  # never called, and `post` is NOT in ModelTest's chain
  def sign_in(user)
    post("/session", params: { u: user })
  end

  def test_it
    puts "model ok"
  end
end

class ControllerTest < IntegrationTest
  # called, and `post` IS in ControllerTest's chain
  def sign_in(user)
    post("/session", params: { u: user })
  end

  def test_it
    sign_in("dave")
  end
end

ModelTest.new.test_it
ControllerTest.new.test_it

# ...and when such a body IS called, it raises at that moment, as CRuby does
class Caller
  def go
    post("/x")
  end
end
r = (Caller.new.go rescue $!.class)
p r
