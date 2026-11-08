# frozen_string_literal: true
# UNIT/component only: no request/cache input is made from these emitted records.
require 'json'
require 'digest'
require_relative 'svg_xml_backend'
manifest = JSON.parse(File.read(ENV.fetch('FIDELITY_SVG_XML_SOURCE_MANIFEST')))
root = manifest.fetch('root')
raise 'SVG XML source root changed' unless File.realpath(root) == root
library = manifest.fetch('library')
raise 'SVG XML library changed' unless Digest::SHA256.hexdigest(File.read(library)) == manifest.fetch('library_sha256')
backend = SvgXmlSymbolsBackend.new(library)
records = {}
manifest.fetch('files').each do |relative, expected|
  path = File.join(root, relative)
  raise 'SVG XML input path escaped source root' unless File.realpath(path).start_with?(root + '/') && !File.symlink?(path)
  source = File.read(path)
  raise 'SVG XML source bytes changed' unless Digest::SHA256.hexdigest(source) == expected
  symbols = backend.symbols_for(File.basename(path, '.svg'), source, strict: true)
  records[relative] = {keys: symbols.keys, count: symbols.size, sha256: Digest::SHA256.hexdigest(JSON.generate(symbols))}
end
# Labelled UNIT vectors exercise actual DOM transformations, never production data.
cases = {
  'regular' => '<svg xmlns="http://www.w3.org/2000/svg"><symbol id="a" viewBox="0 0 1 1"><title>remove</title><path d="M0 0"/></symbol></svg>',
  'brands' => '<svg><symbol id="x" overflow="hidden"><g><title>nested</title><path title="keep attribute"/></g></symbol></svg>',
  'duplicates' => '<svg><symbol id="a"><path id="first"/></symbol><symbol id="b"/><symbol id="a"><path id="last"/></symbol></svg>',
  'entities' => '<svg><symbol id="a&amp;b" data-x="&quot;&amp;&lt;&gt;&apos;"><text>&amp;&lt;&gt;&#xA0;</text></symbol></svg>',
  'comments' => '<svg><symbol id="comment"><!--keep--><![CDATA[keep <text>]]><path/></symbol></svg>',
  'blank' => '<svg><symbol id="&#x3000;"/><symbol id=""/><symbol/><symbol id="ok"/></svg>',
}
unit = {}
cases.each do |filename, xml|
  value = backend.symbols_for(filename, xml, strict: true)
  unit[filename] = {keys: value.keys, sha256: Digest::SHA256.hexdigest(JSON.generate(value))}
end
loose = "<svg>\n <symbol id='loose'>\n  <title>remove</title>\n  <path/>\n </symbol>\n</svg>"
value = backend.symbols_for('loose', loose, strict: false)
unit['loose'] = {keys: value.keys, sha256: Digest::SHA256.hexdigest(JSON.generate(value))}
controls = {}
{
  'doctype' => '<!DOCTYPE svg SYSTEM "file:///unowned.xml"><svg/>',
  'mixed-namespace' => '<svg xmlns="urn:svg"><symbol xmlns="urn:other" id="x"/></svg>',
  'prefixed-root' => '<s:svg xmlns:s="urn:svg"><s:symbol id="x"/></s:svg>',
  'malformed' => '<svg><symbol>',
}.each do |name, xml|
  begin
    backend.symbols_for('unit', xml, strict: true)
    raise 'unsupported SVG XML profile admitted'
  rescue ArgumentError => error
    raise if error.message.empty?
    raise 'SVG XML error leaked document' unless backend.active_documents == 0
    controls[name] = {refused: true, documents_freed: true}
  end
end
raise 'SVG XML component document leak' unless backend.active_documents == 0
puts 'FIDELITY_SVG_XML_COMPONENT ' + JSON.generate({files: records, unit: unit, unit_only_vectors: true, controls: controls, calls: backend.calls, active_documents: backend.active_documents, engine_version: backend.version, request_accepted: false, page_accepted: false})
