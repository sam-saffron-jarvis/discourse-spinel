require "json"
require_relative "../lib/serializers"

def assert(value, label)
  raise label unless value
  puts label
end

record = JSON.parse('{"id":1,"user_id":1,"last_post_user_id":2,"featured_user1_id":3,"featured_user2_id":4,"featured_user3_id":5,"featured_user4_id":6,"created_at_raw":"2026-01-01 00:00:00.000001","bumped_at_raw":"2026-01-01 00:00:00.000002","pinned_at":"2026-01-01","excerpt":"real excerpt","subtype":"regular"}')
serialized = ListableTopicSerializer.new(record).serialize(false, true)
assert(serialized["bumped"] == true, "bumped preserves sub-millisecond comparison")
assert(serialized["pinned"] == true && serialized["unpinned"].nil?, "anonymous pinned/unpinned semantics")
assert(serialized["excerpt"] == "real excerpt", "pinned excerpt included")
record["pinned_at"] = nil
serialized = ListableTopicSerializer.new(record).serialize(false, false)
assert(!serialized.key?("excerpt") && !serialized.key?("featured_link"), "conditional excerpt/featured-link omission")
assert(!serialized.key?("unread") && serialized["unseen"] == false, "anonymous unread fields omitted")
posters = TopicPostersSummary.new(record, [1, 2, 3, 4, 5, 6]).summary
assert(posters.map { |p| p["user_id"] } == [1, 3, 4, 5, 2], "five-poster limit and latest shuffled last")
assert(posters[3]["description"] == "Recent Poster" && posters[1]["description"] == "Frequent Poster", "recent/frequent descriptions")
record["last_post_user_id"] = 1
record["featured_user1_id"] = nil
record["featured_user2_id"] = nil
record["featured_user3_id"] = nil
record["featured_user4_id"] = nil
posters = TopicPostersSummary.new(record, [1]).summary
assert(posters[0]["extras"] == "latest single" && posters[0]["description"] == "Original Poster, Most Recent Poster", "single-poster descriptions/extras")
