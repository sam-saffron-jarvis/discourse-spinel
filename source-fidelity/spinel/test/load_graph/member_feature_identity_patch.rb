module SourceMemberFeature
  class Owner
    def self.patched
      answer + 1
    end
  end
end
$member_feature_events << :patch
