# Source-labelled compiler design control; NOT a production provider.
$member_feature_events = []
module SourceMemberFeature
  class Owner
    def self.singleton_method_added(name)
      $member_feature_events << [:added, name] unless name == :singleton_method_added
    end
    class Child
      def self.read
        DEFAULT
      end
    end
  end
end
$member_feature_events << :helper
