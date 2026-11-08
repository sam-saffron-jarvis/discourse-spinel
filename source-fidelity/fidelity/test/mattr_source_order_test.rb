# frozen_string_literal: true
# Analysis-only controls for the genuine macro. No generated/native macro is
# admitted by these tests; callbacks below belong only to reduced test subjects.
require "minitest/autorun"
require "digest"

source = File.expand_path("../../run/bundle/ruby/4.0.0/gems/activesupport-8.1.4/lib/active_support/core_ext/module/attribute_accessors.rb", __dir__)
raise "original macro source changed" unless Digest::SHA256.file(source).hexdigest == "2d138af1438e8f9091d8ec9e0ed350c067be4748c887cd70cd28fecafaceba60"
require source

module MattrSourceOrderControl
  EVENTS = []
  module Plain
    def self.singleton_method_added(name)
      return if %i[singleton_method_added method_added].include?(name)
      EVENTS << [:class, name, class_variable_defined?(:@@first), class_variable_defined?(:@@second)]
    end

    def self.method_added(name)
      EVENTS << [:instance, name, class_variable_defined?(:@@first), class_variable_defined?(:@@second)]
    end
  end

  # TracePoint observes original Ruby frames and core calls. Ruby 4 has no
  # binding for a C event: sample locals only at Ruby line events, and record
  # a seed only when the actual class_variable_set call happens.
  source = Module.instance_method(:mattr_accessor).source_location.first
  seed = definition = nil
  trace = TracePoint.new(:call, :c_call, :line) do |event|
    next unless event.self.equal?(Plain)
    if event.event == :line && event.path == source
      binding = event.binding
      if binding.local_variable_defined?(:sym_default_value)
        seed = [binding.local_variable_get(:sym), binding.local_variable_get(:sym_default_value)]
      end
      definition = binding.local_variable_get(:definition).dup if binding.local_variable_defined?(:definition)
    elsif event.event == :call && %i[mattr_accessor mattr_reader mattr_writer].include?(event.method_id)
      EVENTS << [:macro, event.method_id]
    elsif event.event == :c_call && event.method_id == :class_variable_set
      EVENTS << [:seed, *seed]
    elsif event.event == :c_call && event.method_id == :module_eval
      EVENTS << [:install, definition]
    end
  end

  trace.enable do
    module Plain
      private
      mattr_accessor :first, :second
      @@first = ["live"]
      mattr_accessor :first
    end
  end

  module BlockDefault
    OBSERVATIONS = []
    mattr_accessor(:value) do
      OBSERVATIONS << [respond_to?(:value), instance_methods(false).include?(:value), class_variable_defined?(:@@value)]
      [OBSERVATIONS.length]
    end
  end

  module OverriddenStorage
    CALLS = []
    def self.class_variable_set(name, value)
      CALLS << [name, value]
      super
    end
    mattr_accessor :value
  end

  module KeywordDefault
    VALUE = []
    CALLS = []
    def self.class_variable_set(name, value)
      CALLS << [name, value.object_id]
      super
    end
    mattr_accessor :value, default: VALUE
  end

  class Instance
    include Plain
  end
end

class MattrSourceOrderTest < Minitest::Test
  Control = MattrSourceOrderControl

  def test_batched_seeds_precede_all_reader_definitions_then_writers
    events = Control::EVENTS
    assert_equal [[:macro, :mattr_accessor], [:macro, :mattr_reader], [:seed, :first, nil], [:seed, :second, nil]], events.first(4)
    installs = events.select { |event| event.first == :install }
    assert_equal [
      "def self.first; @@first; end", "def first; @@first; end",
      "def self.second; @@second; end", "def second; @@second; end",
    ], installs[0][1]
    assert_equal [
      "def self.first=(val); @@first = val; end", "def first=(val); @@first = val; end",
      "def self.second=(val); @@second = val; end", "def second=(val); @@second = val; end",
    ], installs[1][1]
    additions = events.select { |event| %i[class instance].include?(event.first) }
    assert_equal [[:class, :first], [:instance, :first], [:class, :second], [:instance, :second],
                  [:class, :first=], [:instance, :first=], [:class, :second=], [:instance, :second=]], additions.first(8).map { |event| event.first(2) }
    assert additions.all? { |event| event.drop(2) == [true, true] }, "all storage must already exist when definition hooks run"
  end

  def test_nil_redeclaration_preserves_storage_but_reinstalls_both_method_sides
    assert_equal [[:seed, :first, nil], [:seed, :second, nil]], Control::EVENTS.select { |event| event.first == :seed }
    assert_equal 4, Control::EVENTS.count { |event| event.first == :install }
    assert_equal 2, Control::EVENTS.count { |event| event.first(2) == [:class, :first] }
    assert_equal 2, Control::EVENTS.count { |event| event.first(2) == [:instance, :first] }
    assert_equal ["live"], Control::Plain.first
    assert_same Control::Plain.first, Control::Instance.new.first
    assert_nil Control::Plain.second
  end

  def test_private_caller_does_not_make_generated_accessors_private
    %i[first first= second second=].each do |name|
      assert Control::Plain.respond_to?(name), "class accessor #{name} must be public"
      assert Control::Plain.public_instance_methods(false).include?(name), "instance accessor #{name} must be public"
    end
    assert_equal 0, Control::Plain.method(:first).arity
    assert_equal 1, Control::Plain.method(:first=).arity
    assert_equal __FILE__, Control::Plain.method(:first).source_location.first
  end

  def test_accessor_forwards_block_only_to_reader_and_nil_writer_preserves_value
    assert_equal [[false, false, false]], Control::BlockDefault::OBSERVATIONS
    assert_equal [1], Control::BlockDefault.value
  end

  def test_non_nil_keyword_default_seeds_reader_and_writer_with_the_same_evaluated_object
    id = Control::KeywordDefault::VALUE.object_id
    assert_equal [["@@value", id], ["@@value", id]], Control::KeywordDefault::CALLS
    assert_same Control::KeywordDefault::VALUE, Control::KeywordDefault.value
  end

  def test_replacing_original_storage_protocol_with_bare_assignment_is_observable
    assert_equal [["@@value", nil]], Control::OverriddenStorage::CALLS
    assert_nil Control::OverriddenStorage.value
  end
end
