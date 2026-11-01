require "json"
require_relative "../lib/latest"

class SettingRows
  def initialize(pairs)
    @pairs = pairs
  end
  def ntuples
    @pairs.length
  end
  def getvalue(row, column)
    @pairs[row][column]
  end
end

class SettingConnection
  def initialize(pairs)
    @pairs = pairs
  end
  def exec_params(sql, params)
    raise "unexpected setting query" unless sql.start_with?("SELECT name, value FROM site_settings") && params.size == 1
    SettingRows.new(@pairs)
  end
end

def settings(pairs)
  NativeSettings.new(SettingConnection.new(pairs))
end

def check(value, label)
  raise label unless value
  puts label
end

normal = settings([])
normal.validate!
check(normal.enabled?("enable_names", true) && normal.value("default_locale", "en") == "en", "source setting defaults")
check(NativeLatest.more_topics_url(0, false) == "/latest?no_definitions=true&page=1" && NativeLatest.more_topics_url(1, true) == "/latest?page=2", "conditional pagination URL construction")
%w[content_localization_enabled nested_replies_enabled mute_all_categories_by_default empty_box_on_unsolved].each do |name|
  rejected = false
  begin
    settings([[name, "t"]]).validate!
  rescue => error
    rejected = error.message == "unsupported setting: #{name}"
  end
  raise "did not reject #{name}" unless rejected
end
%w[default_avatars logo_small emoji_deny_list].each do |name|
  rejected = false
  begin
    settings([[name, "configured"]]).validate!
  rescue => error
    rejected = error.message == "unsupported setting: #{name}"
  end
  raise "did not reject #{name}" unless rejected
end
puts "unextracted settings fail closed"
user = JSON.parse('{"id":4,"username":"Alice","name":"Alice Example","uploaded_avatar_id":55,"trust_level":2,"admin":true,"moderator":false,"primary_group_id":7,"flair_group_id":7}')
groups = { 7 => JSON.parse('{"id":7,"name":"example","flair_url":"star","flair_bg_color":"ff0000","flair_color":null}') }
serialized = NativeUsers.serialize(user, groups, normal)
check(serialized["avatar_template"] == "/user_avatar/localhost/alice/{size}/55_2.png", "uploaded-avatar path/version adaptation")
check(serialized["primary_group_name"] == "example" && serialized["flair_url"] == "star" && serialized["admin"] == true && !serialized.key?("moderator") && !serialized.key?("flair_color"), "user roles/primary-group/flair conditional fields")
check(!NativeUsers.serialize(user, groups, settings([["enable_names", "f"]])).key?("name"), "enable_names setting respected")
user["id"] = -1
check(NativeUsers.avatar_template(user, normal) == "/images/discourse-logo-sketch-small.png", "system avatar uses source default small logo")
user["id"] = 4
user["username"] = "éloise"
rejected = false
begin
  NativeUsers.avatar_template(user, normal)
rescue => error
  rejected = error.message == "unsupported non-ASCII avatar username"
end
check(rejected, "unextracted Unicode avatar normalization fails closed")
emojis = JSON.parse(File.read("data/emoji-unicode.json"))
check(emojis["wave"] == "👋" && emojis["waving_hand:t2"] == "👋🏻" && emojis["tm"] == "™", "emoji aliases/skin-tones carried from source")
