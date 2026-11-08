require_relative 'member_feature_identity_helper'
module SourceMemberFeature
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
$member_feature_events << :main
