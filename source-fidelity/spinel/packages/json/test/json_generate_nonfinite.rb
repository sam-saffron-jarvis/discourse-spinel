# Infinity and NaN have no JSON spelling: generate refuses them with
# JSON::GeneratorError instead of writing a document no parser reads (#5043).
require "json"
%w[1e309 -1e309].each do |input|
  begin
    puts JSON.generate(JSON.parse(input))
  rescue JSON::GeneratorError => e
    puts "#{e.class}: #{e.message}"
  end
end
begin
  JSON.generate([1, 0.0 / 0.0])
rescue JSON::GeneratorError => e
  puts e.class
end
p JSON.generate([1.5, -0.25])
