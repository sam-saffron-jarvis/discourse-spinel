# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], stylesheet_acquired: false, page_accepted: false}
read = lambda do |path|
  value, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "stylesheet source changed #{path}" unless status.success? && value.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(value)
  value
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "stylesheet method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
application = read.call('app/helpers/application_helper.rb')
manager = read.call('lib/stylesheet/manager.rb')
initializer = select.call(manager, :initialize).slice
getter = select.call(application, :stylesheet_manager).slice.sub('def stylesheet_manager', 'def source_stylesheet_manager')
first = select.call(application, :discourse_color_scheme_stylesheets).body.body.first.slice
partial = read.call('app/views/common/_discourse_stylesheet.html.erb')
raise 'first stylesheet partial expression changed' unless partial.start_with?('<%= discourse_color_scheme_stylesheets %>')
File.write(File.join(build, 'stylesheet_manager_read_source.rb'), "class RequestStyleReadManager\n#{initializer.gsub('Theme.transform_ids', 'ListThemeCompilerSource.transform_ids')}\ndef acquired_theme_id; @theme_id; end\ndef acquired_theme_ids; @theme_ids; end\ndef acquired_themes_cache; @themes_cache; end\nend\nmodule StylesheetManagerReadSource\n#{getter.gsub('Stylesheet::Manager.new', 'RequestStyleReadManager.new')}\ndef discourse_color_scheme_stylesheets\n#{first}\nraise 'stylesheet read boundary unexpectedly returned'\nend\nend\n")
File.write(File.join(build, 'original_stylesheet_manager_read_source.rb'), "class OriginalRequestStyleReadManager\n#{initializer}\ndef acquired_theme_id; @theme_id; end\ndef acquired_theme_ids; @theme_ids; end\ndef acquired_themes_cache; @themes_cache; end\nend\nmodule OriginalStylesheetManagerReadSource\n#{getter.gsub('Stylesheet::Manager.new', 'OriginalRequestStyleReadManager.new')}\ndef discourse_color_scheme_stylesheets\n#{first}\nraise 'original stylesheet read boundary unexpectedly returned'\nend\nend\n")
# Inspect future conditional effects only. Never execute these bodies here.
read.call('lib/stylesheet/manager/builder.rb')
read.call('app/models/stylesheet_cache.rb')
read.call('app/models/theme_field.rb')
proof[:transformations] = ['Actual first stylesheet partial expression and first full helper assignment preserve receiver/argument evaluation', 'Actual source stylesheet_manager defined? memo and Manager initialize/Theme.transform_ids, candidate unique read-role class aliases; raw original separate', 'Only readonly observation accessors; no stylesheet cache registration, seeded CSS, disk hydration, compiler, rebake or PG effect invoked', 'Refuse at first unacquired color stylesheet href/cache/read method; not evidence conditional PG writes dynamically reached']
File.write(File.join(build, 'stylesheet-manager-read-source-proof.json'), JSON.pretty_generate(proof) + "\n")
