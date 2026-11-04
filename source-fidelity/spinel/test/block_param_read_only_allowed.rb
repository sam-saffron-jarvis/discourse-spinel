# The forms beside a block parameter that must keep compiling now that
# assigning to one is refused (test/reject/block_param_assigned.rb).
#
# The check follows Ruby's scoping rather than the name alone: a block
# argument or block-local of the same name is the block's own variable, and
# a nested def is a scope of its own, so none of those is an assignment to
# the parameter.

def reads_only(&b)
  b ? b.call(1) : 0
end

# the rewrite the refusal suggests
def fresh_local(&b)
  blk = b || proc { |n| n * 10 }
  blk.call(2)
end

def no_block_param
  b = 5
  b + 1
end

def block_arg_same_name(&b)
  [1, 2].map { |b| b * 3 }
end

def nested_def(&b)
  def inner
    b = 9
    b
  end
  inner
end

def anon(&)
  1
end

p reads_only { |n| n + 1 }
p reads_only
p fresh_local
p fresh_local { |n| n + 100 }
p no_block_param
p block_arg_same_name { }
p nested_def { }
p anon { }
