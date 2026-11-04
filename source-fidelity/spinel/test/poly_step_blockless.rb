# The blockless step on a boxed receiver, the form #4779 left: it
# materializes the sequence the way the typed emitters do, an Integer or a
# Float array by the box's tag, boxed since the two arms disagree, so
# `.to_a` / `.map` / `.first` read it as the Enumerator's answer. Every
# Integer local is boxed under --int-overflow=promote; the same answers
# there and in the default mode.
v = 1; w = 3
p(v.step(10, w).to_a)
p(v.step(10, w).map { |i| i * 2 })
f = 2.5
p(f.step(9, w).to_a)
n = [3, nil][0]
p(n.step(9, 3).to_a)
g = [2.5, nil][0]
p(g.step(4.0, 0.5).to_a)
p(n.step(5).first)
p(n.step(5).size)
begin
  s = ["a", nil][0]
  s.step(3)
rescue NoMethodError => e
  puts e.message
end
