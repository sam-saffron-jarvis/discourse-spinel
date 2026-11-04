# `Rt = ::Rt` beside `include Rt`: the constant merely ALIASES the module, but
# once two classes hold an alias of that name the collision qualifier rewrites
# every read -- the include's own argument included -- to the owner-qualified
# constant (Consumer__Rt). The include then matched no module and was dropped
# silently, so each receiverless call to a module_function method lost its
# callee and the whole program was refused as an unsupported call.
module Rt
  class Tag
    def wasm_kind = :tag
  end

  module_function

  def check_kind(value, kind)
    value.respond_to?(:wasm_kind) && value.wasm_kind == kind
  end

  def resolve(imports, mod, name)
    source = imports[mod]
    source.respond_to?(:import) ? source.import(name) : source[name]
  end
end

class Provider
  Rt = ::Rt
  EXPORTS = ["t3"].freeze

  def initialize
    @tag3 = Rt::Tag.new
  end

  def import(name)
    return tag_export(name) if EXPORTS.include?(name)
  end

  def tag_export(name)
    case name
    when "t3" then @tag3
    end
  end
end

class Consumer
  Rt = ::Rt
  include Rt

  def initialize(imports = {})
    @tag = check_kind(resolve(imports, "test", "t3"), :tag)
  end

  def linked? = @tag
end

p Consumer.new({ "spectest" => {} }.merge({ "test" => Provider.new })).linked?
p Consumer.new({ "spectest" => {}, "test" => {} }).linked?
