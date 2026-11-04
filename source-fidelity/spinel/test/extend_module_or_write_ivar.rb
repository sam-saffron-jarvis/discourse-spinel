# A method a class gets by `extend` is cloned per class, and the ivars its
# body names become class-level ivars of that class. A body whose only
# mention of an ivar is `@memo ||= v`, `&&=` or `+=` left it unregistered,
# and the clone named a storage slot nothing declared.

module Memo
  def memo = (@memo ||= nil)
  def clear_memo = (@memo &&= nil)
  def bump = (@count = (@count || 0) + 1)
  def tally = (@tally ||= 0; @tally += 2)
end
class A
  extend Memo
end
class B
  extend Memo
end
p A.memo
p B.memo
p A.clear_memo
p A.bump, A.bump, B.bump
p A.tally, A.tally, B.tally
