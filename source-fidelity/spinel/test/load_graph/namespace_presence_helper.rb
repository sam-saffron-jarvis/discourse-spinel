# A helper opens the namespace before its parent's main feature defines
# any class methods. A qualified receiver must use this load point too.
module NamespacePresence
  class Owner
    class Child
      def self.read
        DEFAULT
      end
    end
  end
  Alias = Owner
  raise 'bare future method' if Owner.respond_to?(:answer)
  raise 'qualified future method' if NamespacePresence::Owner.respond_to?(:answer)
  raise 'absolute future method' if ::NamespacePresence::Owner.respond_to?(:answer)
  raise 'aliased future method' if NamespacePresence::Alias.respond_to?(:answer)
  raise 'qualified future private method' if NamespacePresence::Owner.respond_to?(:hidden, true)
  raise 'lost builtin Class surface' unless NamespacePresence::Owner.respond_to?(:new)
end
puts 'namespace helper before methods'
