# `__FILE__`, `__dir__` and `__LINE__` in a required file answer that file:
# its own path, its own directory and its own line, not the entry script's
# (#4839).
require_relative "source_file_required_lib/where"
puts File.basename(Where.file)
puts File.basename(Where.dir)
puts Where.line
puts Where.data
puts File.basename(__FILE__)
puts __LINE__
