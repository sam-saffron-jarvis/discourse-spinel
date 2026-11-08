# A real class-side response protocol stays outside the literal binding fold.
class MemberOwnProtocol
  def self.respond_to?(name, include_all = false)
    name == :own_protocol
  end
end
protocol_owner = MemberOwnProtocol
p [protocol_owner.respond_to?(:own_protocol), protocol_owner.respond_to?(:new)]
