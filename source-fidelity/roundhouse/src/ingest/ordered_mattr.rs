//! Source-positioned Module#mattr/cattr declarations.
//!
//! Literal names use real overridable storage queries/calls, batched paired
//! public definitions, and once-evaluated hygienic keyword-argument captures.
//! Block frames/method-surface timing and nonliteral options remain refused.

use super::prism_api::PrismLocation;
use super::util::{symbol_or_string_value, symbol_value};
use crate::dialect::{MethodDef, MethodReceiver};
use crate::expr::{DeclarationStep, Expr, ExprNode, IrHint, Literal};
use crate::ident::VarId;
use crate::span::Span;
use crate::{ClassId, Symbol};

pub(super) struct Expansion {
    pub initializers: Vec<Expr>,
    pub methods: Vec<MethodDef>,
}

pub(super) fn expand(call: &ruby_prism::CallNode<'_>, owner: &ClassId, file: &str) -> Option<Expansion> {
    if call.block().is_some() {
        return None;
    }
    let kind = std::str::from_utf8(call.name().as_slice()).ok()?;
    if !matches!(
        kind,
        "mattr_reader" | "mattr_writer" | "mattr_accessor" | "cattr_reader" | "cattr_writer" | "cattr_accessor"
    ) {
        return None;
    }
    let mut names = Vec::new();
    let mut default = None;
    for argument in call.arguments()?.arguments().iter() {
        if let Some(name) = symbol_or_string_value(&argument) {
            names.push(name);
        } else if let Some(hash) = argument.as_keyword_hash_node() {
            for element in hash.elements().iter() {
                let assoc = element.as_assoc_node()?;
                if symbol_value(&assoc.key()).as_deref() != Some("default") || default.is_some() {
                    return None;
                }
                let before = super::survey::recorded().len();
                default = Some(super::expr::ingest_expr_strict(&assoc.value(), file).ok()?);
                if super::survey::is_active() && super::survey::recorded().len() != before {
                    return None;
                }
            }
        } else {
            return None;
        }
    }
    if names.is_empty()
        || names.iter().any(|name| {
            let mut chars = name.chars();
            !chars.next().is_some_and(|ch| ch == '_' || ch.is_ascii_alphabetic())
                || !chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
        })
    {
        return None;
    }
    let at = Span {
        file: super::sources::file_id(file),
        start: call.location().start_offset() as u32,
        end: call.location().end_offset() as u32,
    };
    let nil = || Expr::new(at, ExprNode::Lit { value: Literal::Nil });
    let protocol = |method: &str, name: &str, value: Option<Expr>| {
        // ActiveSupport interpolates a fresh mutable String for each call.
        // A Symbol or a shared frozen literal changes the override protocol.
        let mut key = Expr::new(
            at,
            ExprNode::Lit {
                value: Literal::Str {
                    value: format!("@@{name}"),
                },
            },
        );
        key.set_hint(Some(IrHint::MutableStringLiteral));
        let mut args = vec![key];
        if let Some(value) = value {
            args.push(value);
        }
        Expr::new(
            at,
            ExprNode::Send {
                recv: None,
                method: Symbol::from(method),
                args,
                block: None,
                parenthesized: true,
            },
        )
    };
    let mut out = Expansion {
        initializers: Vec::new(),
        methods: Vec::new(),
    };
    let mut ordinal = 0;
    // Call arguments are evaluated once before either phase. A hygienic
    // lexical temporary preserves mutable identity without observable
    // synthetic constants or class-instance-variable slots.
    let captured = default.map(|value| {
        let name = super::expr::fresh_reserved_local(&call.location(), &format!("__rh_mattr_argument_{}", at.start));
        let mut statement = Expr::new(
            at,
            ExprNode::Assign {
                target: crate::expr::LValue::Var {
                    id: VarId(0),
                    name: name.clone(),
                },
                value,
            },
        );
        ordinal += 1;
        statement.set_declaration_step(DeclarationStep { call: at, ordinal });
        out.initializers.push(statement);
        Expr::new(at, ExprNode::Var { id: VarId(0), name })
    });
    for reader in [true, false] {
        if reader && kind.ends_with("_writer") || !reader && kind.ends_with("_reader") {
            continue;
        }
        // Module#mattr_reader and #mattr_writer each seed ALL names, then
        // install their class/instance pairs. Accessor invokes reader first.
        for name in &names {
            let value = captured.clone().unwrap_or_else(nil);
            let query = protocol("class_variable_defined?", name, None);
            let cond = if captured.is_some() {
                Expr::new(
                    at,
                    ExprNode::BoolOp {
                        op: crate::expr::BoolOpKind::And,
                        surface: Default::default(),
                        left: Expr::new(
                            at,
                            ExprNode::Send {
                                recv: Some(value.clone()),
                                method: Symbol::from("nil?"),
                                args: Vec::new(),
                                block: None,
                                parenthesized: true,
                            },
                        ),
                        right: query,
                    },
                )
            } else {
                query
            };
            let mut statement = Expr::new(
                at,
                ExprNode::If {
                    cond,
                    then_branch: nil(),
                    else_branch: protocol("class_variable_set", name, Some(value)),
                },
            );
            ordinal += 1;
            statement.set_declaration_step(DeclarationStep { call: at, ordinal });
            out.initializers.push(statement);
        }
        for name in &names {
            for receiver in [MethodReceiver::Class, MethodReceiver::Instance] {
                let name = Symbol::from(name.as_str());
                let mut method = if reader {
                    super::library_class::synth_mattr_reader(owner, &name, receiver)
                } else {
                    super::library_class::synth_mattr_writer(owner, &name, receiver)
                };
                method.name_span = at;
                ordinal += 1;
                method.body.set_declaration_step(DeclarationStep { call: at, ordinal });
                // The real module_eval defines public methods even under private.
                out.methods.push(method);
            }
        }
    }
    Some(out)
}

/// This intrinsic models the standard Module implementation, not an arbitrary
/// macro by the same name. Refuse source worlds that can replace that protocol
/// or make the synthesized fresh-literal idiom invoke a custom String#+@.
/// The actual class_variable_set override is intentionally NOT excluded.
pub(super) fn validate(app: &crate::App) -> super::IngestResult<()> {
    validate_world(app, false)
}

/// Emit rechecks the world even for direct/deserialized/post-ingest IR.
pub(crate) fn closed_world(app: &crate::App) -> bool {
    validate_world(app, true).is_ok()
}

fn validate_world(app: &crate::App, strict: bool) -> super::IngestResult<()> {
    use super::IngestError;
    fn positioned(expr: &Expr) -> bool {
        expr.declaration_step().is_some()
            && matches!(&*expr.node,
            ExprNode::If { else_branch, .. }
                if matches!(&*else_branch.node, ExprNode::Send { method, .. } if method.as_str() == "class_variable_set"))
    }
    fn macro_protocol(name: &str) -> bool {
        matches!(
            name,
            "mattr_reader"
                | "mattr_writer"
                | "mattr_accessor"
                | "cattr_reader"
                | "cattr_writer"
                | "cattr_accessor"
                | "module_eval"
                | "singleton_class?"
        )
    }
    for owner in app
        .library_classes
        .iter()
        .filter(|class| class.class_ivar_initializers.iter().any(positioned))
    {
        let source = owner
            .class_ivar_initializers
            .iter()
            .find(|expr| positioned(expr))
            .unwrap()
            .span;
        let file = app
            .sources
            .get(source.file.0.saturating_sub(1) as usize)
            .map(|source| source.path.clone())
            .unwrap_or_else(|| "<ordered-mattr>".into());
        let reopened = app
            .library_classes
            .iter()
            .filter(|class| {
                class.name == owner.name && !crate::lower::literal_constant_features::is_feature_reopen(app, class)
            })
            .count()
            != 1;
        let constant_feature = app.library_classes.iter().any(|class| {
            class.name == owner.name && crate::lower::literal_constant_features::is_feature_reopen(app, class)
        });
        let changed = (constant_feature
            && app
                .library_classes
                .iter()
                .any(|class| class.methods.iter().any(|method| method.name.as_str() == "const_added")))
            || owner.methods.iter().any(|method| macro_protocol(method.name.as_str()))
            || owner
                .unknown_calls
                .iter()
                .any(|expr| !matches!(&*expr.node, ExprNode::Send { method, .. } if method.as_str() == "autoload"))
            || app.library_classes.iter().any(|class| {
                (matches!(class.name.0.as_str(), "Module" | "Class")
                    && class.methods.iter().any(|method| {
                        macro_protocol(method.name.as_str())
                            || matches!(method.name.as_str(), "class_variable_set" | "class_variable_defined?")
                    }))
                    || (class.name.0.as_str() == "String"
                        && class.methods.iter().any(|method| method.name.as_str() == "+@"))
                    || (class.name.0.as_str() == "NilClass"
                        && class.methods.iter().any(|method| method.name.as_str() == "nil?"))
            });
        let captured_argument = owner.class_ivar_initializers.iter().any(|expr| {
            expr.declaration_step().is_some()
                && matches!(&*expr.node, ExprNode::Assign { target: crate::expr::LValue::Var { name, .. }, .. }
                if !name.as_str().starts_with('@') && !name.as_str().starts_with('$'))
        });
        let accessor_names: std::collections::BTreeSet<_> = owner
            .methods
            .iter()
            .filter(|method| method.body.declaration_step().is_some())
            .map(|method| method.name.clone())
            .collect();
        let mut versions = std::collections::BTreeSet::new();
        let repeated_definitions = owner
            .methods
            .iter()
            .any(|method| !versions.insert((method.receiver, method.name.clone())));
        let mut dynamic_world = false;
        let mut dynamic_site = None;
        fn mutation(
            expr: &Expr,
            found: &mut bool,
            captured: bool,
            early_calls: &std::collections::BTreeSet<Symbol>,
            site: &mut Option<(Span, String)>,
        ) {
            let before = *found;
            *found |= captured
                && matches!(&*expr.node, ExprNode::Defined { operand } if matches!(&*operand.node, ExprNode::Send { .. }));
            if let ExprNode::Send { method, .. } = &*expr.node {
                // Even identical final bodies are unavailable before the first def.
                // Refuse calls from hooks/storage rather than inventing availability.
                *found |= early_calls.contains(method);
                *found |= captured
                    && matches!(
                        method.as_str(),
                        "respond_to?"
                            | "respond_to_missing?"
                            | "method_defined?"
                            | "public_method_defined?"
                            | "private_method_defined?"
                            | "protected_method_defined?"
                            | "singleton_method"
                            | "methods"
                            | "public_methods"
                            | "private_methods"
                            | "protected_methods"
                            | "singleton_methods"
                            | "instance_methods"
                            | "public_instance_methods"
                            | "private_instance_methods"
                            | "protected_instance_methods"
                            | "method"
                            | "public_method"
                            | "instance_method"
                            | "public_instance_method"
                    );
                *found |= matches!(
                    method.as_str(),
                    "eval"
                        | "binding"
                        | "local_variables"
                        | "class_eval"
                        | "module_eval"
                        | "class_exec"
                        | "module_exec"
                        | "instance_eval"
                        | "instance_exec"
                        | "define_method"
                        | "define_singleton_method"
                        | "remove_method"
                        | "undef_method"
                        | "send"
                        | "public_send"
                        | "__send__"
                        | "const_set"
                        | "remove_const"
                );
            }
            if !before && *found {
                let operation = match &*expr.node {
                    ExprNode::Send { method, .. } => method.as_str().to_string(),
                    _ => "defined? method observation".to_string(),
                };
                *site = Some((expr.span, operation));
            }
            expr.node
                .for_each_child(&mut |child| mutation(child, found, captured, early_calls, site));
        }
        let no_early_calls = std::collections::BTreeSet::new();
        let early_calls = if repeated_definitions {
            &accessor_names
        } else {
            &no_early_calls
        };
        crate::lower::for_each_emit_body_ref(app, &mut |expr| {
            mutation(
                expr,
                &mut dynamic_world,
                captured_argument || repeated_definitions,
                early_calls,
                &mut dynamic_site,
            )
        });
        if !owner.is_module
            || owner.origin.is_some()
            || owner.parent.is_some()
            || !owner.includes.is_empty()
            || reopened
            || changed
            || dynamic_world
        {
            let reason = if reopened {
                "reopened module declaration contexts"
            } else if changed {
                "a changed macro/core protocol or opaque owner-body call"
            } else if dynamic_world {
                "unproved dynamic/reflected application effects"
            } else {
                "a non-root module/ancestor context"
            };
            let detail = dynamic_site
                .and_then(|(span, operation)| {
                    let source = span.file.0.checked_sub(1).and_then(|id| app.sources.get(id as usize))?;
                    Some(format!(
                        "; first unproved operation `{operation}` at {}:{}",
                        source.path,
                        source.line_col(span.start).0
                    ))
                })
                .unwrap_or_default();
            let error = IngestError::Unsupported {
                file,
                message: format!(
                    "ordered plain mattr requires a single module body and an unmodified macro/core protocol: {reason}{detail}; storage-set overrides remain actual calls"
                ),
            };
            if strict {
                return Err(error);
            }
            super::survey::continue_or_fail(error)?;
        }
    }
    Ok(())
}

/// A DeclarationStep alone is not macro provenance. Check the registered
/// source bytes: a direct, receiverless literal declaration in this root
/// module, with precisely this generated side/name/ordinal. The repeated
/// native profile deliberately excludes default/options and nested contexts.
/// This parse is read-only validation, not an ingest/rewrite or source registry.
pub(crate) fn source_accessor_event(
    app: &crate::App,
    owner: &crate::dialect::LibraryClass,
    method: &MethodDef,
) -> bool {
    let Some(step) = method.body.declaration_step() else {
        return false;
    };
    let Some(source) = step
        .call
        .file
        .0
        .checked_sub(1)
        .and_then(|id| app.sources.get(id as usize))
    else {
        return false;
    };
    if method.name_span != step.call
        || method.enclosing_class.as_ref().map(Symbol::as_str) != owner.name.0.as_str().rsplit("::").next()
    {
        return false;
    }
    let parsed = ruby_prism::parse(source.text.as_bytes());
    if parsed.errors().next().is_some() {
        return false;
    }
    let root = parsed.node();
    let Some(program) = root.as_program_node() else {
        return false;
    };
    for statement in program.statements().body().iter() {
        let Some(module) = statement.as_module_node() else {
            continue;
        };
        if super::util::module_name_path(&module)
            .map(|path| path.join("::"))
            .as_deref()
            != Some(owner.name.0.as_str())
        {
            continue;
        }
        let Some(body) = module.body().and_then(|node| node.as_statements_node()) else {
            continue;
        };
        // Includes may have been folded out of the IR before this point;
        // that does not prove an ancestor/macro ownership world here.
        if body.body().iter().any(|stmt| {
            stmt.as_call_node()
                .is_some_and(|call| matches!(call.name().as_slice(), b"include" | b"extend" | b"prepend"))
        }) {
            return false;
        }
        for statement in body.body().iter() {
            let location = statement.location();
            if location.start_offset() != step.call.start as usize || location.end_offset() != step.call.end as usize {
                continue;
            }
            let Some(call) = statement.as_call_node() else {
                return false;
            };
            if call.receiver().is_some() || call.block().is_some() {
                return false;
            }
            let kind = call.name();
            let Ok(kind) = std::str::from_utf8(kind.as_slice()) else {
                return false;
            };
            if !matches!(
                kind,
                "mattr_reader" | "mattr_writer" | "mattr_accessor" | "cattr_reader" | "cattr_writer" | "cattr_accessor"
            ) {
                return false;
            }
            let Some(arguments) = call.arguments() else {
                return false;
            };
            let Some(names) = arguments
                .arguments()
                .iter()
                .map(|arg| symbol_or_string_value(&arg))
                .collect::<Option<Vec<_>>>()
            else {
                return false;
            };
            if names.is_empty() {
                return false;
            }
            let mut ordinal = 0;
            for reader in [true, false] {
                if reader && kind.ends_with("_writer") || !reader && kind.ends_with("_reader") {
                    continue;
                }
                ordinal += names.len() as u32; // Actual storage phase precedes the definitions.
                for name in &names {
                    for receiver in [MethodReceiver::Class, MethodReceiver::Instance] {
                        ordinal += 1;
                        if ordinal != step.ordinal {
                            continue;
                        }
                        let expected = if reader {
                            super::library_class::synth_mattr_reader(
                                &owner.name,
                                &Symbol::from(name.as_str()),
                                receiver,
                            )
                        } else {
                            super::library_class::synth_mattr_writer(
                                &owner.name,
                                &Symbol::from(name.as_str()),
                                receiver,
                            )
                        };
                        // Compare executable shape, not type/diagnostic annotations.
                        return method.name == expected.name
                            && method.receiver == expected.receiver
                            && crate::dialect::staged_identical_accessor_shape(method, &expected);
                    }
                }
            }
            return false;
        }
    }
    false
}
