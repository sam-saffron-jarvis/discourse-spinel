module Where
  def self.file = __FILE__
  def self.dir = __dir__
  def self.line = __LINE__
  def self.data = File.read(File.join(__dir__, "data", "x.txt"))
end
