# frozen_string_literal: true
# Synthetic TEST callback/key/payload used only to exercise the actual original
# registry API and live capture. NOT production plugin registration or SQL.
query = TopicQuery.new(nil, page: 0)
delta = 1
TopicQuery.add_custom_filter(:source_prefix_test) { |result, current_query| result + delta }
delta = 5
raise "original valid-options mutation" unless TopicQuery.valid_options.include?(:source_prefix_test)
raise "original public-options mutation" unless TopicQuery.public_valid_options.include?(:source_prefix_test)
raise "live capture/result frame" unless TopicQuery.apply_custom_filters(1, query) == 6
TopicQuery.remove_custom_filter(:source_prefix_test)
raise "original valid-options removal" if TopicQuery.valid_options.include?(:source_prefix_test)
raise "original public-options removal" if TopicQuery.public_valid_options.include?(:source_prefix_test)
raise "original callback removal" unless TopicQuery.apply_custom_filters(1, query) == 1
puts "original registry API prefix PASS (synthetic callback only)"
