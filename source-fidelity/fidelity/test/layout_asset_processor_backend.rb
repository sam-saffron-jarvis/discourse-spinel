# frozen_string_literal: true
# Platform driver ONLY. The application owns source/lease/lifetime validation.
# No process, network, PG, arbitrary function or caller-chosen logger API.
require "fiddle"
class LayoutAssetProcessorBackend
  def initialize(path)
    @library = Fiddle.dlopen(path)
    @start = Fiddle::Function.new(@library["owned_layout_vm_start"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    @version = Fiddle::Function.new(@library["owned_layout_vm_read_version"], [], Fiddle::TYPE_VOIDP)
    @error = Fiddle::Function.new(@library["owned_layout_vm_error"], [], Fiddle::TYPE_VOIDP)
    @shutdown = Fiddle::Function.new(@library["owned_layout_vm_shutdown"], [], Fiddle::TYPE_INT)
    @started = false
  end
  def start(source, single_threaded)
    @started = true
    result = @start.call(source, single_threaded ? 1 : 0)
    raise "owned native asset VM start failed: #{@error.call.to_s}" unless result == 0
    nil
  end
  def ember_version
    value = @version.call.to_s
    raise "owned native asset VM call failed: #{@error.call.to_s}" if value.empty?
    value
  end
  def compile_messageformat(sources, locales, messages, strict)
    raise 'unowned MessageFormat platform' unless @started
    compiler = Fiddle::Function.new(@library['owned_messageformat_compile'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
    error = Fiddle::Function.new(@library['owned_messageformat_error'], [], Fiddle::TYPE_VOIDP)
    result = compiler.call(sources, locales, messages, strict ? 1 : 0).to_s
    raise "owned MessageFormat compile failed: #{error.call.to_s}" if result.empty?
    result
  end
  def close
    return nil unless @started
    @started = false
    raise "owned native asset VM cleanup failed" unless @shutdown.call == 0
    nil
  end
end
