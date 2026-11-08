# Finite native source-gem file programs

This is a bounded native **graph-loader** profile, selected when source-gem
`FileProgram` IR contains a carried autoload. It is not arbitrary Ruby loading,
framework boot, or a reflective Ruby interpreter. Non-autoload projects and the
existing Ruby-family bootstrap are unchanged.

## Shared plan and execution

`lower/file_programs.rs` resolves a finite set of source features, declaration
owners, literal requires and literal-owner registrations before emission. It
refuses ambiguous/missing resources and merged declaration identities. The
project renderer puts ordinary lowered declaration output inside its original
feature, at its `Declared` event. Declaration paths become require proxies,
not independently executable copies; the eager model aggregator loads only the
original boot roots. Source require calls are not deduplicated.

A compact autoload target may use its literal qualified header only when the
namespace is established on every proved entry path. Its lexical constant reads
are qualified in shared IR first. This does not hoist a namespace, commute body
effects, or run an autoload body early. Inherited/mixin contexts are not admitted
by this initial compact-header proof.

The SAME generated Ruby files execute on CRuby and native Spinel. Native builds
must use `--load-model=graph` (`make build` passes it through the supported spin
compiler-argument seam). Kernel's loader owns cache identity, circular loading,
error propagation, failed-autoload restoration and retry. The reflective
`RoundhouseAutoload` exception helper is neither enabled nor stripped.

## Refusal boundary

Only exact source `defined?` constant-query spans with a proved registration are
admitted at load time. `autoload?`, reflective constant-table APIs, computed or
late registrations, changed search paths/cache state, owner/resource overrides,
rebindings, opaque declaration callbacks and source/resource mutation refuse.
Thread/trace/reflection worlds are outside this finite profile. Ordinary model,
controller and other emitted expression roots are surveyed too: a mutation
cannot hide outside the source-gem declaration bodies.

Static native class metadata is not a general model of fresh Class allocation
on retry. Autoload targets therefore have a deliberately stateless declaration
profile (literal constants, ordinary methods, no class initialization, parent or
mixins). Potential failed-Class value escapes and unproved class-variable
lexical contexts refuse. This is a restriction, not a claim that retry may retain
arbitrary class state. Only exact source sites with proved ordered plain-module
mattr/cattr seed and paired-definition events may compose with this profile (see
`ordered-module-attributes.md`). Unpositioned defaults/blocks remain refused;
the loader does not license changing their storage/definition order.

## Executable control

```
CARGO_BUILD_JOBS=4 cargo test --test native_file_programs -- --nocapture
```

The test runs an original reduced source gem, its lowered Ruby on CRuby, and a
native ELF compiled from those SAME lowered files. It checks registration before
the carried body, lazy/unread effects, nested lexical constants, circular and
repeated requires, failure after a class definition, a visible pending binding
after failure, retry and successful-cache identity across literal absolute and
relative requires. Source files are compared before/after execution. Negative
controls pin the refusal boundary. This proves a compiler capability, not actual
SeedFu, Railtie/plugin initialization, original query or page completion.
