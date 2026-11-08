# Labelled value-object UNIT controls, never query rows/settings/permissions.
poster = TopicPoster.new(flair_group: "initial", extra: false)
raise "initial flair" unless poster.flair_group == "initial"
raise "initial table" unless poster[:extra] == false
raise "missing key" unless poster[:missing].nil?
poster.flair_group = "changed"
poster.user = "user"
poster.description = "description"
poster.extras = "extras"
poster.id = 7
poster.primary_group = "group"
raise "fields" unless poster.user == "user" && poster.description == "description" && poster.extras == "extras"
raise "identity fields" unless poster.id == 7 && poster.primary_group == "group"
raise "flair write" unless poster.flair_group == "changed"
poster["extra"] = 0
raise "table mutation" unless poster[:extra] == 0
copy = poster.to_h
copy[:extra] = 9
raise "table leaked" unless poster[:extra] == 0
raise "declared fields leaked into table" unless poster.to_h == {flair_group: "changed", extra: 0}
raise "attributes" unless poster.attributes == {"user" => "user", "description" => "description", "extras" => "extras", "id" => 7, "primary_group" => "group"}
puts "FIDELITY_TOPIC_POSTER_UNIT app_fields_and_table_equal_ONLY"
