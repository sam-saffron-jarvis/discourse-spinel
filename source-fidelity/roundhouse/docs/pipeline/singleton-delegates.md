# Direct singleton delegate declarations

A literal `delegate` inside the class's own `class << self` installs class
methods. Its `SINGLETON_BODY` source fact must not be lost when the ordinary
instance-delegate lowering consumes declarations. Instance and class delegates
with the same name are separate definitions.

The shared lowering retains these direct singleton declarations as real
`MethodDef`s, at the original macro's `DeclarationStep` and ordinal. Repeated
class definitions and later explicit definitions remain ordered events. Readers
retain ActiveSupport's `...` formal/argument packet, and ordinary writers take
`arg`; the callable ABI is not narrowed to zero arguments. Target evaluation is
once-only. The nil-target NoMethodError rescue, genuine DelegationError call,
allow_nil behavior (including methods nil answers), public generated visibility,
and the actual enclosing owner are retained. Operators/unsupported options stay
unexpanded rather than becoming instance methods. Synthesis failure restores
the original declaration calls. Existing instance specialization and its
zero-width generated-name span convention are unchanged.

Controls compare the installed ActiveSupport 8.1.4 macro with the same shared-IR
Ruby emission: positional Hash versus keywords, blocks/nonlocal return, setter
return, Method arity/parameters, target lookup effects, target/getter exceptions,
nil behavior, visibility, method-definition callbacks and replacement order.
These are reduced compiler controls, not observed application values or native
provider implementations.

**Native support is not granted.** The native forwarding-carrier and source
construction-provenance guards remain unchanged, with an explicit negative test.
The real core input now exposes genuine full-forwarding debt and the required
`safe_each_connection` patch dependency; it is still strictly nonzero and never
executed. Destination resolution must follow actual source construction/field
producers, not borrow an inferred return signature as an argument-contract proof.
A bounded experiment falsified the broad hypothesis that simple factory return
signatures conflate class objects and instances: SelfInstance, an instance Class,
and Class[T] remain distinct. The actual cached producer nevertheless retains
both reachable instance arms and unresolved configuration/body dependencies;
see [the producer boundary](multisite-source-producer-boundary.md). A working
native argument carrier, genuine error runtime and complete source closure still
need proof before this path can be admitted.
