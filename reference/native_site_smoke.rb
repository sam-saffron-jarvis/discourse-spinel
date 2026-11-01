require_relative "native_site"

class ReferenceRows
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

class ReferenceConnection
  attr_reader :queries
  def initialize(promotion = nil, chat = nil)
    @queries = []
    @promotion = promotion
    @chat = chat
  end
  def exec_params(sql, params)
    @queries << [sql, params]
    if sql == "SELECT value FROM site_settings WHERE name = $1" && params == ["enable_public_channels"]
      return ReferenceRows.new(@chat.nil? ? [] : [[@chat]])
    end
    raise "unsafe settings query" unless sql.include?("name = ANY($1::text[])") || sql.include?("FROM uploads")
    if sql.include?("FROM uploads")
      ReferenceRows.new([[-5, "/images/discourse-logo-sketch.png"], [-6, "/images/discourse-logo-sketch-small.png"]])
    else
      rows = [["default_locale", "en"], ["login_required", "f"], ["title", "dynamic title"], ["smtp_password", "never expose"]]
      rows << ["promote_upcoming_changes_on_status", @promotion] if @promotion
      ReferenceRows.new(rows)
    end
  end
  def exec(sql)
    @queries << [sql, []]
    raise "category query is not visibility constrained" unless sql.include?("WHERE c.read_restricted = false")
    ReferenceRows.new([["7", "public", "336699", "ffffff", "public", nil, "1", "f", "f"]])
  end
end

class ImageListConnection
  def exec_params(sql, params)
    ReferenceRows.new([["selectable_avatars", "5"]])
  end
end

def check(value, label)
  raise label unless value
  puts label
end

conn = ReferenceConnection.new
settings = JSON.parse(NativeReference.client_settings_json(conn))
check(settings["default_locale"] == "en" && settings["login_required"] == false && settings["title"] == "dynamic title" && settings["enable_unified_new"] == true && settings["top_menu"] == "latest|new|hot|categories", "client settings use typed live overrides and source upcoming-change defaults")
check(!settings.key?("smtp_password") && settings.length == NativeReference::CLIENT_SETTINGS.length, "client settings exclude unknown rows")
check(NativeReference::CLIENT_SETTINGS.key?("avatar_sizes") && NativeReference::CLIENT_SETTINGS.key?("anon_polling_interval") && NativeReference::CLIENT_SETTINGS.key?("background_polling_interval") && NativeReference::CLIENT_SETTINGS.key?("navigation_menu"), "generated catalog covers browser polling/avatar/navigation settings")
unpromoted = NativeReference.read_client_settings(ReferenceConnection.new("never"))
check(unpromoted["enable_unified_new"] == false && unpromoted["top_menu"] == "latest|new|unread|hot|categories" && !unpromoted.key?("promote_upcoming_changes_on_status"), "dynamic internal promotion threshold changes defaults without being exposed")
rejected_images = false
begin
  NativeReference.read_client_settings(ImageListConnection.new)
rescue => error
  rejected_images = error.message == "nonempty uploaded-image list not extracted"
end
check(rejected_images, "unextracted uploaded-image list fails closed")
site = JSON.parse(NativeReference.site_json(conn))
check(site["trust_levels"]["regular"] == 3 && site["post_types"]["regular"] == 1 && site["notification_types"]["replied"] == 2, "site enums follow source mappings")
check(site["archetypes"][0]["name"] == "Regular Topic" && site["archetypes"].length == 2, "site archetype list excludes private messages and uses source names")
check(site["categories"].length == 1 && site["categories"][0]["name"] == "public", "site categories use anonymous visibility filter")
check(site["hashtag_icons"] == { "category" => "folder", "tag" => "tag", "channel" => "comment" }, "site hashtag icons use source category tag and Chat registry defaults")
check(NativeReference.hashtag_icons(ReferenceConnection.new(nil, "f"), { "tagging_enabled" => false }) == { "category" => "folder" }, "site hashtag icons honor live disabled tag and Chat source predicates")
