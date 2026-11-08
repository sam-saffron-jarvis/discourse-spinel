# frozen_string_literal: true
# Same runtime input and unnormalized output under native/lowered/original Rails.
relative = ENV.fetch("FIDELITY_VENDOR_RELATIVE_PATH")
puts "FIDELITY " + JSON.generate({ kind: "original_vendored_path", root: Rails.root.to_s, input: relative, path: VendoredAssets.path(relative).to_s })
