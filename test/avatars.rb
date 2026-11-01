require_relative "../lib/avatars"

class AvatarRows
  def initialize(rows)
    @rows = rows
  end
  def ntuples
    @rows.length
  end
  def getvalue(row, column)
    @rows[row][column]
  end
end

class AvatarConnection
  attr_reader :params
  def initialize(rows)
    @rows = rows
  end
  def exec_params(sql, params)
    raise "avatar access must verify current public upload" unless sql.include?("u.username_lower=$1 AND up.id=$2::integer AND NOT up.secure")
    @params = params
    AvatarRows.new(@rows)
  end
end

class BlankPaths
  def asset(path)
    raise "wrong fallback" unless path == "/images/avatar.png"
    ["image/png", "actual-stock-asset"]
  end
end

def check(value, name)
  raise name unless value
  puts name
end

conn = AvatarConnection.new([])
avatars = NativeAvatars.new(conn, BlankPaths.new)
check(avatars.call("/user_avatar/localhost/alice/24/10_2.png") == ["image/png", "actual-stock-asset"] && conn.params == ["alice", "10", "24"], "avatar access verifies live username upload size parameters")
check(avatars.call("/letter_avatar_proxy/v4/letter/a/abcdef/24.png") == ["image/png", "actual-stock-asset"], "offline letter avatar explicit source blank fallback")
check(%w[/user_avatar/elsewhere/alice/24/10_2.png /user_avatar/localhost/alice%27/24/10_2.png /user_avatar/localhost/../24/10_2.png /letter_avatar_proxy/v4/letter/a/abcdef/2001.png].all? { |path| avatars.call(path).nil? }, "avatar route storage size and injection boundaries")
rows = AvatarConnection.new([["/uploads/default/original/1X/../../secret.png", "png", nil]])
check(NativeAvatars.new(rows, BlankPaths.new).call("/user_avatar/localhost/alice/24/10_2.png") == ["image/png", "actual-stock-asset"], "avatar database URL traversal is not a filesystem path")
