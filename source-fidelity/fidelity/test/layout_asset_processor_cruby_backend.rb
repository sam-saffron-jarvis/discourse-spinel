# frozen_string_literal: true
# CRuby platform driver counterpart. Executes original MiniRacer lifecycle;
# same application source/owner/lease logic as native, no supplied version.
require "mini_racer"
require "logger"
class LayoutAssetProcessorBackend
  def initialize(path)
    @context = nil
    @lock = Mutex.new
    @logger = Logger.new($stderr)
  end
  def start(source, single_threaded)
    @single_threaded = single_threaded
    MiniRacer::Platform.set_flags!(:single_threaded) if single_threaded
    @context = MiniRacer::Context.new(timeout: 15_000, ensure_gc_after_idle: 2000)
    @context.attach("rails.logger.info", proc { |error| @logger.info(error.to_s); nil })
    @context.attach("rails.logger.warn", proc { |error| @logger.warn(error.to_s); nil })
    @context.attach("rails.logger.error", proc { |error| @logger.error(error.to_s); nil })
    @context.eval(source, filename: "asset-processor.js")
    @context.low_memory_notification
    nil
  end
  def ember_version
    @lock.synchronize do
      value = @context.call_await("emberVersion")
      @context.low_memory_notification if @single_threaded
      value
    end
  end
  def compile_messageformat(sources, locales, messages, strict)
    context = MiniRacer::Context.new(timeout: 10_000)
    begin
      JSON.parse(sources).each { |name, source| context.eval(source, filename: name) }
      context.call('compileMessageFormat', JSON.parse(locales), JSON.parse(messages), strict)
    ensure
      context.dispose
      puts 'FIDELITY_CRUBY_MF_CLEANUP disposed=1'
    end
  end
  def close
    @context.dispose unless @context.nil?
    @context = nil
    nil
  end
end
