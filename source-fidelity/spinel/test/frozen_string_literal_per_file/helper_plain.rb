# frozen_string_literal: false
def plain_helper_lit
  "helper plain lit"
end

def plain_helper_mutate
  s = "plain"
  s << "!"   # FrozenError: the false pragma is ignored (always frozen)
end
