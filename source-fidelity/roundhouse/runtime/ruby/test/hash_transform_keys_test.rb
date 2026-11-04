# frozen_string_literal: true
require "minitest/autorun"
require_relative "../hash_transform_keys"

class HashTransformKeysTest < Minitest::Test
  def test_collision_order_and_aliased_containers
    child = { "flag" => false, "nil" => nil, "empty" => "", "zero" => 0 }
    array = [child]
    hash = { "child" => child, "array" => array, "x" => 1, x: 2 }
    assert_same hash, ActiveSupport.deep_symbolize_keys!(hash)
    assert_same child, hash[:child]
    assert_same array, hash[:array]
    assert_same child, array.first
    assert_equal({ flag: false, nil: nil, empty: "", zero: 0 }, child)
    assert_equal 1, hash[:x]
    refute hash.key?("x")
  end

  def test_non_string_primitive_keys_and_default_are_preserved
    hash = Hash.new(:default)
    [nil, true, false, 7, 1.25, :symbol].each { |key| hash[key] = key }
    before = hash.dup
    assert_same hash, ActiveSupport.deep_symbolize_keys!(hash)
    assert_equal before, hash
    assert_equal :default, hash[:absent]
  end

  def test_frozen_containers_raise_on_real_mutations
    assert_raises(FrozenError) { ActiveSupport.deep_symbolize_keys!({ "key" => 1 }.freeze) }
    # Rails map! raises even for an empty frozen array.
    assert_raises(FrozenError) { ActiveSupport.deep_symbolize_keys!({ "array" => [].freeze }) }
  end

  def test_custom_key_conversion_is_an_explicit_boundary
    assert_raises(NotImplementedError) { ActiveSupport.deep_symbolize_keys!({ Object.new => 1 }) }
  end
end
