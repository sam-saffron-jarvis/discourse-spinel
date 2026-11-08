# frozen_string_literal: true
raise "wrong SeedFu storage owner" unless SeedFu.singleton_class.instance_methods(false).include?(:fixture_paths)
raise "wrong original plugin producer" unless Plugin::Instance.instance_method(:register_seedfu_fixtures).source_location == [File.expand_path("lib/plugin/instance.rb"), 798]
