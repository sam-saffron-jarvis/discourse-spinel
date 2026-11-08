# frozen_string_literal: true
source = VendoredAssets.method(:path).source_location
raise "original VendoredAssets producer changed" unless source == [File.expand_path("lib/vendored_assets.rb"), 8]
raise "original vendor source changed" unless Digest::SHA256.file(source[0]).hexdigest == ENV.fetch("FIDELITY_VENDOR_SOURCE_SHA256")
