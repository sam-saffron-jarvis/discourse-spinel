# frozen_string_literal: true
# Reduced semantic negatives for a PROPOSED staging transformation. These
# passing tests REJECT shortcuts; they do not prove native plugin activation.
require "minitest/autorun"
require "tmpdir"
require "prism"

class StagingSemanticsReceiver
  TOKEN = :receiver_constant
  attr_reader :callback

  def original(source, filename = "original-resource.rb", line = 1)
    target = :caller_local
    instance_eval(source, filename, line)
  end

  def original_return
    instance_eval("return :script_return", "original-resource.rb", 1)
    :suffix_ran
  end

  def staged_return(code)
    instance_eval(&code)
    :suffix_ran
  end

  def capture(&block)
    @callback = block
  end
end

module StagingSemanticsLexical
  TOKEN = :lexical_constant
  def self.constant_body
    proc { TOKEN }
  end
  def self.local_body
    proc { defined?(target) }
  end
  def self.location_body
    proc { [__FILE__, __LINE__] }
  end
  def self.return_body
    proc { return :script_return }
  end
  def self.capture_body
    proc { capture { self } }
  end
end

class SourceStagingSemanticsTest < Minitest::Test
  def test_same_self_and_nested_callback_owner_is_necessary_but_not_sufficient
    owner = StagingSemanticsReceiver.new
    owner.original("capture { self }")
    assert_same owner, owner.callback.call
    owner.instance_eval(&StagingSemanticsLexical.capture_body)
    assert_same owner, owner.callback.call
    assert_same owner, owner.callback.binding.receiver
  end

  def test_staged_literal_keeps_its_lexical_constants_not_string_eval_constants
    owner = StagingSemanticsReceiver.new
    assert_equal :receiver_constant, owner.original("TOKEN")
    assert_equal :lexical_constant, owner.instance_eval(&StagingSemanticsLexical.constant_body)
  end

  def test_eval_sees_actual_caller_locals_but_an_external_block_does_not
    owner = StagingSemanticsReceiver.new
    assert_equal :caller_local, owner.original("target")
    assert_equal "local-variable", owner.original("defined?(target)")
    assert_nil owner.instance_eval(&StagingSemanticsLexical.local_body)
  end

  def test_source_filename_and_line_are_not_fixed_by_rebinding_self
    owner = StagingSemanticsReceiver.new
    assert_equal ["actual-resource.rb", 41], owner.original("[__FILE__, __LINE__]", "actual-resource.rb", 41)
    refute_equal ["actual-resource.rb", 41], owner.instance_eval(&StagingSemanticsLexical.location_body)
  end

  def test_nonlocal_return_targets_the_activation_frame_not_a_proc_factory
    owner = StagingSemanticsReceiver.new
    assert_equal :script_return, owner.original_return
    assert_raises(LocalJumpError) { owner.staged_return(StagingSemanticsLexical.return_body) }
    # A lambda avoids the LocalJumpError but then wrongly executes the suffix.
    assert_raises(ArgumentError) { owner.staged_return(-> { return :script_return }) }
    assert_equal :suffix_ran, owner.staged_return(->(_) { return :script_return })
  end

  def test_relative_require_tracks_the_source_filename_not_the_staging_file
    Dir.mktmpdir("source-staging-semantics-") do |root|
      original = File.join(root, "original")
      staged = File.join(root, "staged")
      Dir.mkdir(original)
      Dir.mkdir(staged)
      File.write(File.join(original, "helper.rb"), "$source_staging_require_observation = :original\n")
      File.write(File.join(staged, "helper.rb"), "$source_staging_require_observation = :staged\n")
      StagingSemanticsReceiver.new.original('require_relative "helper"', File.join(original, "plugin.rb"))
      assert_equal :original, $source_staging_require_observation
      # Parse a literal block where the proposed staging file would live.
      code = Object.class_eval('proc { require_relative "helper" }', File.join(staged, "capsule.rb"), 1)
      StagingSemanticsReceiver.new.instance_eval(&code)
      assert_equal :staged, $source_staging_require_observation
    ensure
      $source_staging_require_observation = nil
    end
  end

  def test_constructor_proc_relocation_must_not_reread_a_rebound_class_constant
    namespace = Module.new
    first = Class.new
    second = Class.new
    namespace.const_set(:Factory, first)
    captured_class = namespace.const_get(:Factory)
    original = -> { captured_class.new }
    relocated = -> { namespace.const_get(:Factory).new }
    namespace.send(:remove_const, :Factory)
    namespace.const_set(:Factory, second)
    assert_instance_of first, original.call
    assert_instance_of second, relocated.call
  end

  def test_declaration_hoisting_changes_observable_event_order
    declaration = 'module ::SourceStagingOrderExample; $source_staging_events << :module_body; end'
    configure = '$source_staging_events << :configuration'
    register = '$source_staging_events << :initializer_registration'
    owner = StagingSemanticsReceiver.new
    $source_staging_events = []
    owner.original([configure, declaration, register].join("\n"))
    original = $source_staging_events.dup
    $source_staging_events = []
    owner.original([declaration, configure, register].join("\n"))
    assert_equal [:configuration, :module_body, :initializer_registration], original
    refute_equal original, $source_staging_events
  ensure
    $source_staging_events = nil
    Object.send(:remove_const, :SourceStagingOrderExample) if Object.const_defined?(:SourceStagingOrderExample, false)
  end
end
