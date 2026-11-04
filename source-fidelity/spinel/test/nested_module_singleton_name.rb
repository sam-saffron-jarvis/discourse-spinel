# A singleton `name`, `to_s` or `inspect` defined on a NESTED module or class
# (#4526): the shadow check that lets a user singleton win over the builtin
# stringification only knew a top-level constant receiver, so
# `Outer::Nested.name(bytes)` answered the constant path and dropped the
# argument. A constant path receiver is keyed by its leaf like the rest.
module Outer
  module Nested
    def self.name(bytes) = bytes.first.to_s
    def self.to_s(bytes) = bytes.last.to_s
  end
end
module TopLevel
  def self.name(bytes) = bytes.first.to_s
end
p Outer::Nested.name([7, 9])
p Outer::Nested.to_s([7, 9])
p TopLevel.name([7, 9])
module Outer
  class NestedClass
    def self.name(bytes) = bytes.first.to_s
    def self.inspect(bytes) = "i#{bytes.size}"
  end
  module ClassSelfForm
    class << self
      def name(bytes) = bytes.first.to_s
    end
  end
  module Plain
  end
end
p Outer::NestedClass.name([7, 9])
p Outer::NestedClass.inspect([7, 9])
p Outer::ClassSelfForm.name([7, 9])
p Outer::Plain.name
p Outer::Plain.to_s
p Outer::NestedClass.to_s
