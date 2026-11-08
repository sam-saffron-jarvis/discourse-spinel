# The built-in fallback must fit the boxed result beside user returns.
require "ostruct"
require "date"
class OtherResult
  def path = {unit: "path"}
  def day = {unit: "day"}
end
def path_of(value)
  value.path
end
def day_of(value)
  value.day
end
File.open(__FILE__) do |file|
  puts path_of(file).end_with?("boxed_path_day_fallback.rb")
end
Dir.open(".") do |directory|
  p path_of(directory)
end
p path_of(OtherResult.new)
p day_of(Time.utc(2026, 11, 5))
p day_of(Date.new(2026, 11, 6))
p day_of(OtherResult.new)
