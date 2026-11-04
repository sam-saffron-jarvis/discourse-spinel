# A private method called with an explicit receiver is NoMethodError also
# when the receiver is boxed (a block parameter over an array of objects);
# self., send and a protected call from the declaring class still work
# (#4920).
class Bar
  private def hid? = true
  protected def prot = 7
  def via_self = self.hid?
  def peer(o) = o.prot
end
begin; p [Bar.new].any? { |x| x.hid? }; rescue NoMethodError => e; puts "NoMethodError: #{e.message}"; end
begin; [Bar.new].each { |y| p y.prot }; rescue NoMethodError => e; puts "NoMethodError: #{e.message}"; end
p [Bar.new].map { |x| x.send(:hid?) }
p [Bar.new].map { |x| x.via_self }
p [Bar.new].map { |x| x.peer(Bar.new) }
