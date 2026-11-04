class MyError < StandardError
end

err = MyError.new("boom")
begin
  raise err
rescue MyError => e
  puts "caught: #{e.message}"
end
