# spinel: gc-stress
# A failed typed hash pattern must not fetch from nil or a missing key.
class NullablePatternTable
  def initialize
    @table = nil
  end
  def set(value)
    @table = {key: value}
  end
  def literal
    case @table
    in {key: 7} then :seven
    in nil then :nil
    else :other
    end
  end
  def typed
    case @table
    in {key: Integer} then :integer
    in nil then :nil
    else :other
    end
  end
  def alternative
    case @table
    in {key: 7} | {missing: Integer} then :match
    in nil then :nil
    else :other
    end
  end
  def expression
    @table in {key: Integer}
  end
  def missing_default
    @table = Hash.new { raise "pattern fetched a missing key" }
    @table[:key] = "other"
  end
end
table = NullablePatternTable.new
p [table.literal, table.typed, table.alternative, table.expression]
table.set(7)
p [table.literal, table.typed, table.alternative, table.expression]
table.set("other")
p [table.literal, table.typed, table.alternative, table.expression]
table.missing_default
p [table.literal, table.typed, table.alternative, table.expression]
