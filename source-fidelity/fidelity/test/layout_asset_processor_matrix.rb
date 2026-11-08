# frozen_string_literal: true
# Component caller only. Actual cached source is input; never original output.
require "json"
require_relative "layout_asset_processor_backend"
engine = LayoutAssetProcessorBackend.new(ENV.fetch("FIDELITY_VM_LIBRARY"))
begin
  source = File.read(ENV.fetch("FIDELITY_VM_SOURCE"))
  mode = ENV.fetch("FIDELITY_VM_SINGLE_THREADED")
  raise "unknown component VM configuration" unless mode == "1" || mode == "0"
  engine.start(source, mode == "1")
  first = engine.ember_version
  second = engine.ember_version
  raise "retained original VM version changed" unless first == second
  puts "FIDELITY_VM_DRIVER " + JSON.generate({value: first, ruby_class: first.class.name, retained_calls: 2, html_accepted: false})
ensure
  engine.close
end
