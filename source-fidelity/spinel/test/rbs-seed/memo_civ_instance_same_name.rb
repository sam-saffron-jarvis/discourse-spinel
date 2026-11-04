# spinel: rbs-seed-run
# Class and instance state share a spelling, not a Ruby object or value.
class MixedMemoOwner
  def initialize
    @table = 41
  end
  def marker
    @table
  end
  def self.table
    @table ||= {}
  end
  def self.populate
    @table = {}
    @table["key"] = "class value"
  end
end
value = MixedMemoOwner.new
p value.marker
p MixedMemoOwner.table.empty?
MixedMemoOwner.populate
p MixedMemoOwner.table["key"]
p value.marker

class MixedArrayOwner
  def initialize
    @items = "instance marker"
  end
  def marker
    @items
  end
  def self.items
    @items ||= []
  end
  def self.populate
    @items = []
    @items << "class item"
  end
end
item = MixedArrayOwner.new
p MixedArrayOwner.items.empty?
MixedArrayOwner.populate
p MixedArrayOwner.items[0].upcase
p item.marker
