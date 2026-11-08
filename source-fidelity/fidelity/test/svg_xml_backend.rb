# frozen_string_literal: true
# SAME platform adapter on Spinel and CRuby: native stateless libxml2, no Ruby child.
require 'fiddle'
require 'json'
class SvgXmlSymbolsBackend
  def initialize(path)
    @library = Fiddle.dlopen(path)
    @symbols = Fiddle::Function.new(@library['owned_svg_xml_symbols'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
    @error = Fiddle::Function.new(@library['owned_svg_xml_error'], [], Fiddle::TYPE_VOIDP)
    @active = Fiddle::Function.new(@library['owned_svg_xml_active_documents'], [], Fiddle::TYPE_LONG)
    @calls = Fiddle::Function.new(@library['owned_svg_xml_calls'], [], Fiddle::TYPE_LONG)
    @version = Fiddle::Function.new(@library['owned_svg_xml_version'], [], Fiddle::TYPE_VOIDP)
  end
  def symbols_for(filename, source, strict:)
    raise TypeError, 'SVG XML source arguments' unless filename.is_a?(String) && source.is_a?(String) && (strict == true || strict == false)
    payload = @symbols.call(source, source.bytesize, filename, strict ? 1 : 0).to_s
    raise 'SVG XML document cleanup leaked' unless active_documents == 0
    raise ArgumentError, @error.call.to_s if payload.empty?
    value = JSON.parse(payload)
    raise TypeError, 'SVG XML symbol map type' unless value.is_a?(Hash) && value.all? { |key, xml| key.is_a?(String) && xml.is_a?(String) }
    value
  end
  def active_documents; @active.call; end
  def calls; @calls.call; end
  def version; @version.call.to_s; end
end
