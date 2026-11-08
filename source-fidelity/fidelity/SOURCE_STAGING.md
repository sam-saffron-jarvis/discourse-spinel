# Finite source staging: semantic boundary (Recovery11)

**No source-eval staging mechanism is admitted by this document or probe.**
Original `Plugin::Instance#activate!` evaluates a whole script at935 before its
asset/locales/service-worker/seed/task/migration/link/image suffix. Those effects
and complete initializers/registrations remain required. Neither a three-name
registry seed nor raw source pasted around shared IR satisfies this boundary.

Run the analysis-only audit with an actual successful producer observation:

```
python3 tools/probe_source_staging.py --trace build/probe-original-query-20261104-202008/evidence.json
```

The tool checks pinned whole-script bytes against that producer evidence. It
parses but **never executes** the scripts. Assign/events/solved contain1/6/1
class/module declarations,11/14/3returns and5/39/2relative requires. Parsing a
literal block inside the original method fails Ruby's declaration grammar for
all3scripts. Moving it outside the method fixes grammar, not semantics. The
actual caller locals are `auto_assets`, `migration_paths`, `public_data`, `target`;
no binding collisions were observed for those names in these inputs, but that
is not a generic license to discard the caller frame.

Reduced executable controls demonstrate:

- Self rebinding and nested callback owner can match while other semantics fail.
- String instance-eval's receiver constant lookup differs from the staging
  block's lexical lookup.
- Eval can read its caller's locals; an external block cannot acquire them by
  rebinding self.
- `__FILE__`, `__LINE__` and `require_relative` follow source origin, not self.
  Rewriting requires also needs canonical feature/cache identity and failure
  semantics, not merely a path that happens to load.
- A nonlocal return belongs to the activation frame. A Proc factory frame can
  already be gone; changing to a lambda changes both arity and suffix execution.
- Hoisting a declaration can reorder its body effects against configuration and
  initializer registration. Pure-looking class/module headers are not effect
  proofs; method/inherited/constant hooks and bodies matter.
- Replacing a captured class argument with a lambda rereading its constant
  changes constructor identity after rebinding. The registry's `type.new`-only
  use does not alone prove such a rewrite safe.

Actual APIs `add_to_class`, `add_class_method`, `validate` and serializer helpers
bind some source blocks as real methods. Those return frames must be distinguished
from ordinary stored callbacks; do not blanket-rewrite every `return`. The actual
solved filter is Class-owned and captures two original lambdas, unlike assign and
events' plugin-instance-owned callbacks. Configuration/YAML/provider and callback
order comes from the original observed boot, never from staged cached answers.

## Chosen bounded route

Rather than extend intentional native string eval or assert an unproved block
rewrite, Recovery11 closes a concrete dependency of the measured complete original
registry: its `Archetype` reference205. The complete original Archetype initially
refuses the genuine `ActiveModel::Serialization` include. Complete package-verified
ActiveModel8.1.4 source, with its MIT license, supplies that include; no empty
module or application header is manufactured. Default declarations, registration,
replacement/deregistration, options aliasing, default serialization and negative
controls are executable proof obligations, not a claim about every serialization
option, full registry or activation.

The lifecycle probe exposed an additional real compiler issue: Prism's indexed
assignment syntax had been ingested as an explicit `[]=` call, giving original
`Archetype.register` a nil return signature. Shared assignment IR must answer the
RHS while an explicit overridden `obj.[]=(key,value)` keeps its method return.
Receiver/key/RHS order, once-only effects, identity and exceptions are guarded.

The remaining first-class `HashWithIndifferentAccess` values remain refused.
Roundhouse models that abstraction as a String-keyed Hash, **not a runtime Class**.
Any future constructor specialization needs closed use/escape proofs, captured
class binding/identity, laziness, callback/frame/order and unknown-world guards;
never add a fake constant/class to make the two registry declarations type-check.

Finite-source activation still needs a shared-IR source-program/frame mechanism
with origin, lexical context, captures, control transfer, resource identity guards
and complete effect closure. Unknown resources/worlds must refuse before execution.
No emitter-only passthrough, arbitrary eval waiver or callback omission is allowed.
