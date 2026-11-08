require_relative 'member_feature_identity_helper'
owner = SourceMemberFeature::Owner
raise 'main API exposed in helper' if owner.respond_to?(:answer)
raise 'private API exposed in helper' if owner.respond_to?(:hidden, true)
raise 'builtin Class constructor absent' unless owner.respond_to?(:new)
raise 'patch API exposed in helper' if owner.respond_to?(:patched)
begin
  SourceMemberFeature::Owner::Child.read
  raise 'future constant exposed in helper'
rescue NameError
  $member_feature_events << :constant_absent
end
require_relative 'member_feature_identity_main'
raise 'main value changed' unless SourceMemberFeature::Owner.answer == 42
raise 'loaded main API absent through local' unless owner.respond_to?(:answer)
raise 'private API public' if owner.respond_to?(:hidden)
raise 'private API absent' unless owner.respond_to?(:hidden, true)
raise 'patch hoisted into main' if SourceMemberFeature::Owner.respond_to?(:patched)
require_relative 'member_feature_identity_patch'
raise 'patch value changed' unless SourceMemberFeature::Owner.patched == 43
raise 'class binding replaced' unless SourceMemberFeature::Owner.equal?(owner)
require_relative 'member_feature_identity_patch'
expected = [:helper, :constant_absent, [:added, :answer], [:added, :hidden], :main, [:added, :patched], :patch]
raise 'source class callbacks/features reordered' unless $member_feature_events == expected
p $member_feature_events
puts 'source member feature identity compiler control PASS; NOT core support'

# Captured/conditional writers are NOT a single source binding witness.
class OtherMemberIdentity
  def self.other
    1
  end
end
captured_owner = SourceMemberFeature::Owner
1.times { captured_owner = OtherMemberIdentity }
raise 'captured class write ignored' if captured_owner.respond_to?(:answer)
raise 'captured class write lost' unless captured_owner.respond_to?(:other)
conditional_owner = SourceMemberFeature::Owner
conditional_owner = OtherMemberIdentity if ARGV.empty?
raise 'conditional class write ignored' if conditional_owner.respond_to?(:answer)
raise 'conditional class write lost' unless conditional_owner.respond_to?(:other)
puts 'source class local writer controls PASS'
