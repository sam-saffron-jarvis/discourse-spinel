# frozen_string_literal: true
# Native standard Emoji.exists? probes. Source verifier uses actual Emoji.[];
# data here is package-derived, never captured Rails output.
require "json"
require_relative "../lib/emoji_existence"
probes = NativeEmoji::CATALOG.fetch("standard").keys + NativeEmoji::CATALOG.fetch("aliases").keys
probes += %w[heart:t1 heart:t2 wave:t1 wave:t2 wave:t6 +1:t2 thumbsup:t3 :wave: :wave:t1: :+1:t4: tm trade_mark not_real not_real:t2]
probes += [nil, "", ":", "::", "wave:t7"]
results = probes.uniq.map do |name|
  value = begin
    NativeEmoji.exists?(name)
  rescue
    "invalid"
  end
  { "name" => name, "exists" => value }
end
raise "standard names must exist" unless results.any? { |row| row["name"] == "tm" && row["exists"] == true }
raise "toned aliases must exist" unless results.any? { |row| row["name"] == "+1:t2" && row["exists"] == true }
File.write("build/emoji-existence-native.json", JSON.generate({ "source_only" => true, "probes" => results }))
puts "PASS native source emoji existence, alias and tone normalization"
