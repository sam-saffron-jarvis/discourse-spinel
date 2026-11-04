# A braceless keyword hash that no keyword parameter claims packs into the
# first unfilled positional parameter (`def check(sel, opts = nil)` called
# `check(".x", count: 0)`). The ordinary call paths have done this since
# #3191; a call that gets INLINED because the callee yields looked the keys up
# by parameter name only, so `opts` kept its default and a test helper's
# `assert_select(sel, count: 0)` asserted presence instead. (#4436)
def check(selector, opts = nil, &block)
  if opts.is_a?(Hash) && opts[:count] == 0
    puts "#{selector}: count zero"
  elsif opts.is_a?(Hash) && opts[:text]
    puts "#{selector}: text #{opts[:text]}"
  else
    puts "#{selector}: presence"
  end
  yield if block
end

def sel(selector, content_or_opts = nil, opts = nil)
  h = opts || (content_or_opts.is_a?(Hash) ? content_or_opts : nil)
  puts "#{selector}: #{content_or_opts.inspect} #{h.inspect}"
  yield if block_given?
end

check(".message", count: 0)
check(".title", text: "hi")
check(".a") { puts "  in block" }
check(".b", count: 0) { puts "  in block" }
check(".c", { count: 0 })
h = { count: 0 }
check(".d", h)
sel(".e", count: 0)
sel(".f", "body", count: 1) { puts "  in block" }
