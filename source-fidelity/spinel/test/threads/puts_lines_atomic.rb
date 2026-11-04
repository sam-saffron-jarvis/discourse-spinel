# puts from several threads: each line lands whole. The emitters used to
# write the text and the newline as two stdio calls, and another worker's
# puts could land between them, gluing two lines together and leaving an
# empty one. Checked by shape, since the interleaving of whole lines is
# free to vary.
ts = (0...8).map { |w| Thread.new(w) { |wid| 300.times { |i| puts "#{wid}/#{i}" } } }
ts.each(&:join)
