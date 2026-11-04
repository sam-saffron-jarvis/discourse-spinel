# spinel: rbs-seed-contradicted-return
# Boxing separate homes must not discard the class reader's Hash contract.
class MixedBadWriter
  def initialize
    @table = 41
  end
  def marker
    @table
  end
  def self.table
    @table ||= {}
  end
  def self.poison
    @table = 81
  end
end
p MixedBadWriter.new.marker
MixedBadWriter.poison
p MixedBadWriter.table
