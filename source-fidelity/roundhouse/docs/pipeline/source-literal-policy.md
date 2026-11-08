# Source literal policy in declaration and resource plans

The genuine Discourse multisite freedom patch has `frozen_string_literal: true`.
A separate full-Rails postboot renderer control found its static lookup String
thawed by shared-IR emission, even though callback returns, nonlocal returns and
method formals matched. The old failing comparison is retained. This is source
allocation semantics, not permission to freeze settings or captured values.

The shared `source_literal_policy` analysis reads the retained source metadata
of static literal IR spans, including method/default/body/conditional contexts.
It joins policies over the declarations sharing an output file. Finite resource
programs carry their own composed policy over declaration and statement steps.
A homogeneous frozen-source group emits its original file directive. It does
NOT insert String#freeze calls, invoke an overridable method or freeze runtime
DB/provider values. Existing explicit fresh-literal IR remains fresh.

Mixed source policies in one physical declaration/resource file refuse rather
than guess a common directive. Per-expression allocation IR would be needed to
admit that broader case. Synthetic framework literals keep their existing
policy. This repair does not claim general literal ownership or fix native
construction before a later initialize.

Tests cover original/shared-Ruby/native frozen state, literal identity,
FrozenError, explicit mutable copies and mutation, plus a String#freeze override
that would catch a synthetic-freeze workaround. All fifteen finite file-program
controls now pass, including the previously retained frozen-version failure.
The complete original multisite patch is checked without removed yield/rescue/
DEFAULT lookup clauses. Separate guarded full-Rails postboot carriers compare
its emitted methods; they are explicitly NOT candidate bootstrap, standalone
compatibility or native provider acceptance. The genuine native forwarding and
multi-feature class-lifetime refusals remain in place.
