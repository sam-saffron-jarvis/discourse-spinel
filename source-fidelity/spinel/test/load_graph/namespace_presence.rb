require_relative 'namespace_presence_helper'
module NamespacePresence
  class Owner
    DEFAULT = 41
    def self.answer
      Child.read + 1
    end
    def self.hidden
      7
    end
    private_class_method :hidden
  end
end
raise 'qualified loaded method absent' unless NamespacePresence::Owner.respond_to?(:answer)
raise 'absolute loaded method absent' unless ::NamespacePresence::Owner.respond_to?(:answer)
raise 'aliased loaded method absent' unless NamespacePresence::Alias.respond_to?(:answer)
raise 'qualified private visible' if NamespacePresence::Owner.respond_to?(:hidden)
raise 'qualified private missing' unless NamespacePresence::Owner.respond_to?(:hidden, true)
raise 'late lexical lookup changed' unless NamespacePresence::Owner.answer == 42
puts 'namespace main after methods'
