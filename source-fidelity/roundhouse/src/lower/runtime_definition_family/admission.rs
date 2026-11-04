//! Reject-only boundary for the first concrete, zero-argument family. A
//! virtual slot is not a native Method/Module table: unsupported observations
//! and escapes must keep the original runtime-definition refusal intact.
use super::*;

const OVERRIDES: &[&str] = &[
    "define_singleton_method",
    "singleton_class",
    "respond_to?",
    "respond_to_missing?",
    "method_missing",
    "send",
    "__send__",
    "public_send",
    "method",
    "public_method",
    "private_class_method",
    "public_class_method",
    "instance_variable_get",
    "instance_variable_set",
    "__method__",
    "__callee__",
    "const_added",
    "==",
    "equal?",
    "hash",
    "eql?",
    "superclass",
    "inherited",
];
const UNSUPPORTED: &[&str] = &[
    "methods",
    "public_methods",
    "private_methods",
    "protected_methods",
    "singleton_methods",
    "singleton_method",
    "instance_method",
    "public_instance_method",
    "instance_methods",
    "public_instance_methods",
    "private_instance_methods",
    "protected_instance_methods",
    "method_defined?",
    "public_method_defined?",
    "private_method_defined?",
    "protected_method_defined?",
    "remove_method",
    "undef_method",
    "define_method",
    "extend",
    "include",
    "prepend",
    "instance_eval",
    "instance_exec",
    "class_eval",
    "class_exec",
    "module_eval",
    "module_exec",
    "freeze",
    "dup",
    "clone",
    "binding",
    "eval",
    "set_trace_func",
    "trace_var",
    "defined?",
    "constants",
    "const_get",
    "const_defined?",
    "const_set",
    "const_source_location",
];

pub(super) fn shape(app: &App, family: &Family) -> bool {
    // Generated containers/callables/token comparison use core protocols.
    // Reopenings could change them without changing native Method semantics.
    if app.library_classes.iter().any(|class| {
        matches!(
            class.name.0.as_str(),
            "String"
                | "Symbol"
                | "Integer"
                | "Float"
                | "Array"
                | "Hash"
                | "Proc"
                | "Method"
                | "TrueClass"
                | "FalseClass"
                | "NilClass"
                | "NameError"
                | "NoMethodError"
        )
    }) {
        return false;
    }
    for class in app
        .library_classes
        .iter()
        .filter(|class| family.descendants.contains(&class.name.0))
    {
        if class.is_module
            || !class.includes.is_empty()
            || class.origin.is_some()
            || !class.conditional_definitions.is_empty()
            || app
                .library_classes
                .iter()
                .filter(|other| other.name == class.name)
                .count()
                != 1
            || class.methods.iter().any(|method| {
                method.receiver == MethodReceiver::Class
                    && OVERRIDES.contains(&method.name.as_str())
            })
            || !family.callback
                && class.methods.iter().any(|method| {
                    method.receiver == MethodReceiver::Class
                        && method.name.as_str() == "singleton_method_added"
                })
        {
            return false;
        }
        // The first owning family runs after class loading. A class-body
        // factory callback needs a proven helper-load dependency seam first.
        if class.unknown_calls.iter().any(|expr| {
            let visibility = matches!(&*expr.node,
                ExprNode::Send { recv: None, method, block: None, .. }
                    if matches!(method.as_str(), "private_class_method" | "public_class_method"));
            !visibility
                && (family.extensions.is_empty()
                    || expr.decisions & crate::expr::REPLAYED_CLASS_BODY == 0)
        }) {
            return false;
        }
        for method in &class.methods {
            let class_side = method.receiver == MethodReceiver::Class;
            if !body(&method.body, family, class_side, &mut Env::new())
                || !observed_values(&method.body, family, class_side)
            {
                return false;
            }
            for default in method
                .params
                .iter()
                .filter_map(|param| param.default.as_ref())
            {
                if !body(default, family, class_side, &mut Env::new()) {
                    return false;
                }
            }
        }
        for expr in class
            .unknown_calls
            .iter()
            .chain(&class.class_ivar_initializers)
            .chain(class.constants.iter().map(|(_, value)| value))
        {
            if !body(expr, family, true, &mut Env::new()) {
                return false;
            }
        }
    }
    for module in app
        .library_classes
        .iter()
        .filter(|module| family.extensions.contains(&module.name))
    {
        if !module.includes.is_empty()
            || module.origin.is_some()
            || !module.unknown_calls.is_empty()
            || !module.conditional_definitions.is_empty()
            || module.methods.iter().any(|method| {
                method.receiver == MethodReceiver::Class
                    && matches!(
                        method.name.as_str(),
                        "extend_object"
                            | "append_features"
                            | "prepend_features"
                            | "const_added"
                            | "singleton_method_added"
                    )
            })
        {
            return false;
        }
        let Some(hook) = module.methods.iter().find(|method| {
            method.receiver == MethodReceiver::Class && method.name.as_str() == "extended"
        }) else {
            return false;
        };
        if hook.params.len() != 1
            || hook.block_param.is_some()
            || hook.params.iter().any(|param| {
                param.default.is_some() || param.rest || param.keyword || param.forwarding
            })
            || module.methods.iter().any(|method| {
                method.receiver == MethodReceiver::Instance
                    && (method.block_param.is_some()
                        || method.params.iter().any(|param| {
                            param.default.is_some()
                                || param.rest
                                || param.keyword
                                || param.forwarding
                        }))
            })
        {
            return false;
        }
        for method in &module.methods {
            let context = method.receiver == MethodReceiver::Instance;
            let mut closed = true;
            walk(&method.body, &mut |expr| {
                // A future virtual getter has no native signature before this
                // pass. Its replacement is nevertheless closed by this
                // family's already-typed template and zero-argument ABI.
                let virtual_call = match &*expr.node {
                    ExprNode::Send {
                        recv,
                        method,
                        args,
                        block: None,
                        ..
                    } if owner_receiver(recv.as_ref(), family, context).is_some() => {
                        (matches!(method.as_str(), "send" | "__send__" | "public_send")
                            && args.len() == 1
                            && family_name(&args[0], &Env::new(), family))
                            || (family.names.contains(method) && args.is_empty())
                    }
                    _ => false,
                };
                fn installation_result(expr: &Expr, family: &Family) -> bool {
                    if let ExprNode::Seq { exprs } = &*expr.node {
                        return exprs
                            .last()
                            .is_some_and(|last| installation_result(last, family));
                    }
                    family.sites.iter().any(|site| {
                        site.original.span == expr.span && site.original.node == expr.node
                    })
                }
                closed &= expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown())
                    || virtual_call
                    || installation_result(expr, family);
            });
            if !closed
                || !body(&method.body, family, context, &mut Env::new())
                || !observed_values(&method.body, family, context)
            {
                return false;
            }
        }
    }
    let mut valid = true;
    super::super::for_each_emit_body_ref(app, &mut |expr| {
        valid &= body(expr, family, false, &mut Env::new()) && observed_values(expr, family, false)
    });
    valid
}

fn compatible(actual: &Ty, expected: &Ty) -> bool {
    if actual == expected {
        return true;
    }
    match (actual, expected) {
        (Ty::Union { variants }, _) => variants.iter().all(|actual| compatible(actual, expected)),
        (_, Ty::Union { variants }) => variants.iter().any(|expected| compatible(actual, expected)),
        (Ty::Hash { key: ak, value: av }, Ty::Hash { key: ek, value: ev }) => {
            compatible(ak, ek) && compatible(av, ev)
        }
        (Ty::Array { elem: actual }, Ty::Array { elem: expected }) => compatible(actual, expected),
        _ => false,
    }
}
fn stored_value(value: &Expr, expected: &Ty) -> bool {
    if matches!((&*value.node, expected.peel_nilable()),
        (ExprNode::Hash { entries, .. }, Ty::Hash { .. }) if entries.is_empty())
    {
        return true;
    }
    if matches!((&*value.node, expected.peel_nilable()),
        (ExprNode::Array { elements, .. }, Ty::Array { .. }) if elements.is_empty())
    {
        return true;
    }
    value
        .ty
        .as_ref()
        .is_some_and(|actual| compatible(actual, expected))
}

fn body(expr: &Expr, family: &Family, class_side: bool, env: &mut Env) -> bool {
    if let ExprNode::Seq { exprs } = &*expr.node {
        return exprs.iter().all(|expr| body(expr, family, class_side, env));
    }
    if let ExprNode::Assign {
        target: LValue::Var { name, .. },
        value,
    } = &*expr.node
    {
        env.insert(name.clone(), domain(value, env));
    }
    if class_side
        && matches!(&*expr.node, ExprNode::Send { recv: None, method, args, block: None, .. }
        if method.as_str() == "extend" && matches!(args.as_slice(), [argument] if matches!(&*argument.node, ExprNode::Const { path } if family.extensions.contains(&crate::analyze::mixin_path_id(path)))))
    {
        return true;
    }
    let mut valid = true;
    match &*expr.node {
        ExprNode::Assign {
            target: LValue::Ivar { name },
            value,
        } if class_side => {
            if let Some(expected) = family.storage.get(name).or_else(|| {
                family
                    .storage_patterns
                    .iter()
                    .find(|pattern| {
                        format!("@{name}").starts_with(&pattern.prefix)
                            && format!("@{name}").ends_with(&pattern.suffix)
                    })
                    .map(|pattern| &pattern.value)
            }) {
                valid &= stored_value(value, expected);
            }
        }
        ExprNode::Assign {
            target: LValue::Index { recv, .. },
            value,
        } if class_side => {
            if let ExprNode::Ivar { name } = &*recv.node
                && let Some(expected) = family.storage.get(name)
            {
                valid &= match expected.peel_nilable() {
                    Ty::Hash { value: element, .. } | Ty::Array { elem: element } => {
                        stored_value(value, element)
                    }
                    _ => false,
                };
            }
        }
        ExprNode::Defined { operand } => {
            if class_side {
                return false;
            }
            walk(operand, &mut |node| {
                if let ExprNode::Send { recv, .. } = &*node.node {
                    valid &= owner_receiver(recv.as_ref(), family, class_side).is_none();
                }
            });
        }
        // Generated lookup errors preserve their exception class, but the
        // full VM NameError/NoMethodError record/stack is not this protocol.
        ExprNode::BeginRescue { rescues, .. }
            if class_side && rescues.iter().any(|clause| clause.binding.is_some()) =>
        {
            return false;
        }
        ExprNode::Var { name, .. } if name.as_str().starts_with("__rh_") => return false,
        ExprNode::Send {
            recv,
            method,
            args,
            block,
            ..
        } => {
            if method.as_str() == "define_singleton_method"
                && owner_receiver(recv.as_ref(), family, class_side).is_some()
            {
                // Never lower only a supported subset of one owner's events.
                return family.sites.iter().any(|site| {
                    site.original.span == expr.span && site.original.node == expr.node
                });
            }
            if method.as_str() == "singleton_class"
                && owner_receiver(recv.as_ref(), family, class_side).is_some()
            {
                return false; // only the enclosing, proven alias form below consumes this
            }
            if method.as_str() == "alias_method"
                && let Some(recv) = recv
                && let ExprNode::Send {
                    recv: owner,
                    method: singleton,
                    args: noargs,
                    block: None,
                    ..
                } = &*recv.node
                && singleton.as_str() == "singleton_class"
                && noargs.is_empty()
                && owner_receiver(owner.as_ref(), family, class_side).is_some()
            {
                return block.is_none()
                    && args.len() == 2
                    && args.iter().all(|arg| family_name(arg, env, family));
            }
            if owner_receiver(recv.as_ref(), family, class_side).is_some() {
                if UNSUPPORTED.contains(&method.as_str()) {
                    return false;
                }
                if matches!(
                    method.as_str(),
                    "instance_variable_get" | "instance_variable_set"
                ) && block.is_some()
                {
                    return false;
                }
                if method.as_str() == "instance_variable_set" {
                    let field = args.first().and_then(|arg| match &*arg.node {
                        ExprNode::Lit {
                            value: Literal::Sym { value },
                        } => value.as_str().strip_prefix('@'),
                        ExprNode::Lit {
                            value: Literal::Str { value },
                        } => value.as_str().strip_prefix('@'),
                        _ => None,
                    });
                    let expected = if let Some(field) = field {
                        family.storage.get(&Symbol::from(field)).or_else(|| {
                            family
                                .storage_patterns
                                .iter()
                                .find(|pattern| {
                                    format!("@{field}").starts_with(&pattern.prefix)
                                        && format!("@{field}").ends_with(&pattern.suffix)
                                })
                                .map(|pattern| &pattern.value)
                        })
                    } else {
                        let Some(address) = args.first().and_then(storage::address) else {
                            return false;
                        };
                        let Some(pattern) = family.storage_patterns.iter().find(|pattern| {
                            (pattern.prefix.as_str(), pattern.suffix.as_str())
                                == (address.0.as_str(), address.1.as_str())
                        }) else {
                            return false;
                        };
                        Some(&pattern.value)
                    };
                    if let Some(expected) = expected {
                        valid &= args.len() == 2 && stored_value(&args[1], expected);
                    }
                }
                let names = args.first().map(|arg| domain(arg, env)).unwrap_or_default();
                if matches!(method.as_str(), "method" | "public_method")
                    && !family.extension_apis.is_empty()
                    && (names.is_empty() || !names.is_disjoint(&family.extension_apis))
                {
                    return false;
                }
                if let Some(arity) = family.extension_arities.get(method) {
                    valid &= args.len() == *arity && block.is_none();
                }
                if matches!(method.as_str(), "send" | "__send__" | "public_send") {
                    for name in &names {
                        if let Some(arity) = family.extension_arities.get(name) {
                            valid &= args.len() == *arity + 1 && block.is_none();
                        }
                    }
                }
                let touches = names.is_empty()
                    || !names.is_disjoint(&family.names)
                    || family.open_names && names.is_disjoint(&family.native_names);
                match method.as_str() {
                    "respond_to?" => {
                        valid &= block.is_none()
                            && (args.len() == 1 || args.len() == 2)
                            && args[0].ty.as_ref().is_some_and(Ty::is_stringish)
                            && args.get(1).is_none_or(|arg| arg.ty == Some(Ty::Bool))
                    }
                    "send"
                    | "__send__"
                    | "public_send"
                    | "method"
                    | "public_method"
                    | "private_class_method"
                    | "public_class_method"
                        if touches =>
                    {
                        valid &=
                            block.is_none() && args.len() == 1 && family_name(&args[0], env, family)
                    }
                    _ if family.names.contains(method)
                        || family.open_names && !family.native_names.contains(method) =>
                    {
                        valid &= args.is_empty() && block.is_none()
                    }
                    _ => {}
                }
            }
        }
        _ => {}
    }
    expr.node
        .for_each_child(&mut |child| valid &= body(child, family, class_side, &mut env.clone()));
    super::forget_nested_writes(expr, env);
    valid
}

pub(super) fn template(body: &Expr) -> bool {
    let mut valid = true;
    walk(body, &mut |expr| {
        valid &= expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown());
        if let ExprNode::Lambda {
            params,
            rest_param,
            extra_params,
            block_param,
            ..
        } = &*expr.node
        {
            valid &= !params
                .iter()
                .chain(rest_param)
                .chain(block_param)
                .chain(extra_params.iter().map(|param| &param.name))
                .any(|name| name.as_str().starts_with("__rh_"));
        }
        valid &= !matches!(
            &*expr.node,
            ExprNode::Return { .. }
                | ExprNode::Super { .. }
                | ExprNode::Yield { .. }
                | ExprNode::Break { .. }
                | ExprNode::Next { .. }
                | ExprNode::Retry
                | ExprNode::Redo
                | ExprNode::Defined { .. }
                | ExprNode::OpAssign {
                    target: LValue::Ivar { .. },
                    ..
                }
                | ExprNode::MultiAssign { .. }
        );
        if let ExprNode::Send { method, .. } = &*expr.node {
            valid &= !matches!(
                method.as_str(),
                "method"
                    | "public_method"
                    | "singleton_method"
                    | "respond_to?"
                    | "send"
                    | "__send__"
                    | "public_send"
                    | "instance_eval"
                    | "instance_exec"
                    | "class_eval"
                    | "class_exec"
                    | "module_eval"
                    | "module_exec"
                    | "define_singleton_method"
                    | "define_method"
                    | "binding"
                    | "eval"
                    | "block_given?"
                    | "caller"
                    | "caller_locations"
                    | "local_variables"
            );
        }
        if let ExprNode::Var { name, .. } | ExprNode::Let { name, .. } = &*expr.node {
            valid &= !name.as_str().starts_with("__rh_");
        }
    });
    valid
}

fn bound_value(expr: &Expr, family: &Family, class_side: bool, locals: &Names) -> bool {
    matches!(&*expr.node, ExprNode::Var { name, .. } if locals.contains(name))
        || matches!(&*expr.node, ExprNode::Send { recv, method, args, block: None, .. }
            if matches!(method.as_str(), "method" | "public_method") && args.len() == 1
                && owner_receiver(recv.as_ref(), family, class_side).is_some())
}

fn observed_values(expr: &Expr, family: &Family, class_side: bool) -> bool {
    let mut locals = Names::new();
    loop {
        let before = locals.len();
        walk(expr, &mut |node| {
            if let ExprNode::Assign {
                target: LValue::Var { name, .. },
                value,
            } = &*node.node
                && bound_value(value, family, class_side, &locals)
            {
                locals.insert(name.clone());
            }
        });
        if locals.len() == before {
            break;
        }
    }
    // Only locals actually read by an installation in THIS executable
    // root are lexical owner captures, not arbitrary escaped Class aliases.
    let mut captures = Names::new();
    walk(expr, &mut |candidate| {
        if family.sites.iter().any(|site| {
            site.original.span == candidate.span && site.original.node == candidate.node
        }) && let ExprNode::Send {
            block: Some(block), ..
        } = &*candidate.node
        {
            walk(block, &mut |child| {
                if let ExprNode::Var { name, .. } = &*child.node {
                    captures.insert(name.clone());
                }
            });
        }
    });
    fn check(
        expr: &Expr,
        family: &Family,
        class_side: bool,
        locals: &Names,
        captures: &Names,
        bound_ok: bool,
        class_ok: bool,
    ) -> bool {
        if let ExprNode::Send { recv, method, .. } = &*expr.node
            && method.as_str() == "define_singleton_method"
            && owner_receiver(recv.as_ref(), family, class_side).is_some()
        {
            return true;
        }
        if let ExprNode::Send { recv, method, .. } = &*expr.node
            && matches!(
                method.as_str(),
                "private_class_method" | "public_class_method"
            )
            && owner_receiver(recv.as_ref(), family, class_side).is_some()
        {
            return class_ok;
        }
        if bound_value(expr, family, class_side, locals) {
            return bound_ok;
        }
        if owner_receiver(Some(expr), family, class_side).is_some() {
            return class_ok;
        }
        match &*expr.node {
            ExprNode::Seq { exprs } => exprs.iter().enumerate().all(|(index, expr)| {
                check(
                    expr,
                    family,
                    class_side,
                    locals,
                    captures,
                    false,
                    index + 1 < exprs.len(),
                )
            }),
            ExprNode::Assign {
                target: LValue::Var { name, .. },
                value,
            } if locals.contains(name) => {
                check(value, family, class_side, locals, captures, true, false)
            }
            ExprNode::Assign {
                target: LValue::Var { name, .. },
                value,
            } if captures.contains(name)
                && owner_receiver(Some(value), family, class_side).is_some() =>
            {
                // A lexical owner capture before the installation may be used
                // by its typed template. The assignment must not return the
                // Class out of the factory; later owner-valued reads still
                // pass the same escape/observer checks as the original self.
                class_ok && check(value, family, class_side, locals, captures, false, true)
            }
            ExprNode::Send {
                recv: Some(recv),
                method,
                args,
                block,
                ..
            } if bound_value(recv, family, class_side, locals) => {
                if block.is_some() {
                    return false;
                }
                if method.as_str() == "==" {
                    return args.len() == 1 && bound_value(&args[0], family, class_side, locals);
                }
                // A bound receiver is a Class value. Do not let it escape to
                // unrewritten native method-table operations.
                if method.as_str() == "receiver" && !class_ok {
                    return false;
                }
                args.is_empty()
                    && matches!(
                        method.as_str(),
                        "call" | "name" | "original_name" | "receiver" | "arity"
                    )
            }
            ExprNode::Send {
                recv,
                method,
                args,
                block,
                ..
            } => {
                let identity = matches!(method.as_str(), "equal?" | "==" | "!=");
                recv.as_ref().is_none_or(|recv| {
                    let bound_receiver = matches!(&*recv.node, ExprNode::Send { recv: Some(bound), method, .. }
                        if method.as_str() == "receiver" && bound_value(bound, family, class_side, locals));
                    check(recv, family, class_side, locals, captures, false, !bound_receiver || identity)
                })
                    && args.iter().all(|arg| check(arg, family, class_side, locals, captures, false, identity))
                    && block.as_ref().is_none_or(|block| check(block, family, class_side, locals, captures, false, false))
            }
            _ => {
                let mut valid = true;
                expr.node.for_each_child(&mut |child| {
                    valid &= check(child, family, class_side, locals, captures, false, false)
                });
                valid
            }
        }
    }
    check(expr, family, class_side, &locals, &captures, false, false)
}
