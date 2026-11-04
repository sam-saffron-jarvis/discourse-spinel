# Per-file frozen_string_literal under Spinel: literals are ALWAYS frozen.
# A `# frozen_string_literal: false` pragma is not supported -- it warns at
# compile time and is ignored, so the helper's literals freeze exactly like
# every other file's (helper_frozen has the true pragma, helper_plain the
# ignored false, this entry file none).
require_relative "frozen_string_literal_per_file/helper_frozen"
require_relative "frozen_string_literal_per_file/helper_plain"

p frozen_helper_lit.frozen?   # true -- explicit true pragma
p plain_helper_lit.frozen?    # true -- explicit false pragma is ignored
p "entry lit".frozen?         # true -- no pragma: always frozen

begin
  frozen_helper_mutate
  puts "BUG: no raise"
rescue FrozenError => e
  puts e.message
end

begin
  plain_helper_mutate
  puts "BUG: no raise"
rescue FrozenError => e
  puts e.message
end
