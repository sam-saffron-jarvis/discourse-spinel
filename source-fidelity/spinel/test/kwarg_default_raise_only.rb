# A keyword whose default only raises -- the Rails shape for a keyword the
# caller must pass. The default gives the parameter no value, so it must not
# type it: typed from it the parameter was void, which no C slot holds, and a
# call leaving it out refused to compile.
class Feed
  def recent(amount, sub: false, for_user: (raise "undefined local variable or method 'user'"))
    [amount, sub, for_user]
  end

  def only(for_user: (raise "no user"))
    for_user
  end
end

f = Feed.new
p f.recent(3, for_user: 5)
begin
  f.recent(3)
rescue => e
  p e.message
end
begin
  f.only
rescue => e
  p e.message
end
