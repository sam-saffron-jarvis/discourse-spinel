# A mutable String's object_id is the same however it is reached: read
# straight from the local, from a copy of the reference, or back out of a
# box (an Array or Hash element, a block parameter over mixed elements).
# The typed read used to copy the text each time and take the copy's
# address, so no two reads agreed.

class Box
  def empty? = true
end

t = +"x"
t << "y"
[t, Box.new].each { |x| p x.object_id == t.object_id }
u = t
p u.object_id == t.object_id
p t.object_id == t.object_id
a = [t]
p a[0].object_id == t.object_id
h = { k: t }
p h[:k].object_id == t.object_id
p t.equal?(a[0])

# a different String with the same text is a different object
v = +"x"
v << "y"
p v.object_id == t.object_id
