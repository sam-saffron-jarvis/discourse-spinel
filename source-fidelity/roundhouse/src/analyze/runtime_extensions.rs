//! Source-owned class-load extension events. The module and real `extend`
//! remain executable source; this records who receives its instance producers
//! and the real `extended` callback, never copied state or eager definitions.
use crate::app::RuntimeExtensionEvent;
use crate::dialect::{MethodReceiver, ModelBodyItem};
use crate::expr::{Expr, ExprNode};
use crate::{App, ClassId};

fn path(expr: &Expr) -> Option<ClassId> {
    let ExprNode::Const { path } = &*expr.node else {
        return None;
    };
    Some(crate::analyze::mixin_path_id(path))
}
fn extension(expr: &Expr) -> Option<ClassId> {
    let ExprNode::Send {
        recv: None,
        method,
        args,
        block: None,
        ..
    } = &*expr.node
    else {
        return None;
    };
    if method.as_str() != "extend" {
        return None;
    }
    let [module] = args.as_slice() else {
        return None;
    };
    path(module)
}
fn walk(expr: &Expr, f: &mut impl FnMut(&Expr)) {
    f(expr);
    expr.node.for_each_child(&mut |child| walk(child, f));
}

pub(crate) fn prepare(app: &mut App) {
    if !app.runtime_extension_events.is_empty() {
        return;
    }
    let sole = app.sole_extender_of_modules();
    let mut events = Vec::new();
    for module in app.library_classes.iter().filter(|class| class.is_module) {
        let Some(owner) = sole.get(&module.name) else {
            continue;
        };
        let mut producer = false;
        for method in module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Instance)
        {
            walk(&method.body, &mut |expr| {
                producer |= matches!(&*expr.node, ExprNode::Send { recv: None, method, .. } if method.as_str() == "define_singleton_method");
            });
        }
        if !producer {
            continue;
        }
        let mut sites = Vec::new();
        for class in app
            .library_classes
            .iter()
            .filter(|class| &class.name == owner)
        {
            sites.extend(
                class
                    .unknown_calls
                    .iter()
                    .filter(|call| extension(call).as_ref() == Some(&module.name))
                    .cloned(),
            );
        }
        for model in app.models.iter().filter(|model| &model.name == owner) {
            sites.extend(model.body.iter().filter_map(|item| match item {
                ModelBodyItem::Unknown { expr, .. }
                    if extension(expr).as_ref() == Some(&module.name) =>
                {
                    Some(expr.clone())
                }
                _ => None,
            }));
        }
        // Repeated/dynamic extension and module-object escapes need a richer
        // domain proof. A source class-method read does not mix its instance
        // producers into another object and remains ordinary module dispatch.
        let [site] = sites.as_slice() else { continue };
        let mut safe = true;
        fn uses(
            expr: &Expr,
            module: &ClassId,
            site: &Expr,
            class_methods: &[crate::Symbol],
            safe: &mut bool,
        ) {
            if expr.span == site.span && expr.node == site.node {
                return;
            }
            if let ExprNode::Send {
                recv: Some(receiver),
                method,
                args,
                block,
                ..
            } = &*expr.node
                && path(receiver).as_ref() == Some(module)
                && class_methods.contains(method)
                && !matches!(method.as_str(), "extended" | "extend_object")
            {
                for arg in args {
                    uses(arg, module, site, class_methods, safe);
                }
                if let Some(block) = block {
                    uses(block, module, site, class_methods, safe);
                }
                return;
            }
            if path(expr).as_ref() == Some(module) {
                *safe = false;
                return;
            }
            expr.node
                .for_each_child(&mut |child| uses(child, module, site, class_methods, safe));
        }
        let methods: Vec<_> = module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Class)
            .map(|method| method.name.clone())
            .collect();
        crate::lower::for_each_emit_body_ref(app, &mut |expr| {
            uses(expr, &module.name, site, &methods, &mut safe)
        });
        if safe {
            events.push(RuntimeExtensionEvent {
                module: module.name.clone(),
                owner: owner.clone(),
                original: site.clone(),
            });
        }
    }
    app.runtime_extension_events = events;
}

/// The source definition behind an owner's folded class-side surface. This is
/// parameter evidence routing, not a copied MethodDef or a new dispatch table.
/// Ambiguous competing modules remain uninferred; an owner's own def wins.
pub(super) fn parameter_targets(
    app: &App,
) -> std::collections::BTreeMap<(ClassId, crate::Symbol), ClassId> {
    let mut targets = std::collections::BTreeMap::new();
    for event in &app.runtime_extension_events {
        let Some(module) = app
            .library_classes
            .iter()
            .find(|class| class.name == event.module)
        else {
            continue;
        };
        for method in module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Instance)
        {
            let own = app
                .library_classes
                .iter()
                .filter(|class| class.name == event.owner)
                .flat_map(|class| &class.methods)
                .any(|candidate| {
                    candidate.receiver == MethodReceiver::Class && candidate.name == method.name
                })
                || app
                    .models
                    .iter()
                    .filter(|model| model.name == event.owner)
                    .flat_map(|model| model.methods())
                    .any(|candidate| {
                        candidate.receiver == MethodReceiver::Class && candidate.name == method.name
                    });
            if own {
                continue;
            }
            let calls = app
                .library_classes
                .iter()
                .filter(|class| class.name == event.owner)
                .flat_map(|class| class.unknown_calls.iter())
                .chain(
                    app.models
                        .iter()
                        .filter(|model| model.name == event.owner)
                        .flat_map(|model| {
                            model.body.iter().filter_map(|item| match item {
                                ModelBodyItem::Unknown { expr, .. } => Some(expr),
                                _ => None,
                            })
                        }),
                );
            let competing = calls.into_iter().any(|call| {
                let ExprNode::Send {
                    method: name,
                    args,
                    block,
                    ..
                } = &*call.node
                else {
                    return false;
                };
                if name.as_str() != "extend" {
                    return false;
                }
                if block.is_some() {
                    return true;
                }
                args.iter().any(|arg| {
                    let Some(other) = path(arg) else { return true };
                    other != event.module
                        && app
                            .library_classes
                            .iter()
                            .filter(|class| class.name == other)
                            .any(|class| {
                                !class.includes.is_empty()
                                    || class.methods.iter().any(|candidate| {
                                        candidate.receiver == MethodReceiver::Instance
                                            && candidate.name == method.name
                                    })
                            })
                })
            });
            if !competing {
                targets.insert(
                    (event.owner.clone(), method.name.clone()),
                    event.module.clone(),
                );
            }
        }
    }
    targets
}

/// Source writes through a proven memoized Hash reader belong to the same
/// extender storage as direct ivar writes. Retain only types, never values.
pub(super) fn collect_storage_fields(
    app: &App,
    fields: &mut crate::det::HashMap<ClassId, crate::det::HashMap<crate::Symbol, crate::ty::Ty>>,
) {
    use crate::expr::{LValue, OpAssignOp};
    use crate::ty::Ty;
    let targets = parameter_targets(app);
    for event in &app.runtime_extension_events {
        let Some(module) = app
            .library_classes
            .iter()
            .find(|class| class.name == event.module)
        else {
            continue;
        };
        let owner_fields = fields.entry(event.owner.clone()).or_default();
        let mut readers = std::collections::BTreeMap::new();
        for method in module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Instance)
        {
            if method.params.is_empty()
                && method.block_param.is_none()
                && targets.get(&(event.owner.clone(), method.name.clone())) == Some(&event.module)
                && let ExprNode::OpAssign {
                    target: LValue::Ivar { name },
                    op: OpAssignOp::OrOr,
                    value,
                } = &*method.body.node
                && matches!(&*value.node, ExprNode::Hash { entries, .. } if entries.is_empty())
            {
                // The empty seed has no elements to constrain: its previous
                // inferred annotation is not another runtime writer. Rebuild
                // from this round's real writes, including unresolved ones.
                owner_fields
                    .entry(name.clone())
                    .or_insert_with(|| Ty::Hash {
                        key: std::sync::Arc::new(Ty::Var {
                            var: crate::ident::TyVar(0),
                        }),
                        value: std::sync::Arc::new(Ty::Var {
                            var: crate::ident::TyVar(0),
                        }),
                    });
                readers.insert(method.name.clone(), name.clone());
            } else {
                super::extract_ivar_assignments(&method.body, owner_fields);
            }
        }
        fn owner_receiver(receiver: Option<&Expr>, owner: &ClassId, implicit: bool) -> bool {
            match receiver.map(|receiver| &*receiver.node) {
                None | Some(ExprNode::SelfRef) => implicit,
                Some(ExprNode::Const { path: written }) => super::mixin_path_id(written) == *owner,
                _ => receiver.is_some_and(|receiver| matches!(&receiver.ty, Some(Ty::Class { id, args })
                    if id.0.as_str() == "Class" && matches!(args.as_slice(), [Ty::Class { id, .. }] if id == owner))),
            }
        }
        let collect =
            |body: &Expr,
             implicit: bool,
             owner_fields: &mut crate::det::HashMap<crate::Symbol, Ty>| {
                walk(body, &mut |expr| {
                    let (receiver, key, value) = match &*expr.node {
                        ExprNode::Send {
                            recv: Some(receiver),
                            method,
                            args,
                            block: None,
                            ..
                        } if method.as_str() == "[]=" && args.len() == 2 => {
                            (receiver, &args[0], &args[1])
                        }
                        ExprNode::Assign {
                            target: LValue::Index { recv, index },
                            value,
                        } => (recv, index, value),
                        _ => return,
                    };
                    let ExprNode::Send {
                        recv,
                        method,
                        args,
                        block: None,
                        ..
                    } = &*receiver.node
                    else {
                        return;
                    };
                    let Some(field) = readers.get(method) else {
                        return;
                    };
                    if !args.is_empty() || !owner_receiver(recv.as_ref(), &event.owner, implicit) {
                        return;
                    }
                    // Unknown writers are debt, not permission to invent a key or
                    // drop a value arm because a different writer was concrete.
                    let observed = |expr: &Expr| {
                        expr.ty
                            .clone()
                            .filter(|ty| !ty.mentions_unknown())
                            .unwrap_or(Ty::Untyped)
                    };
                    super::widen_hash_ivar_value(
                        owner_fields,
                        field,
                        Some(observed(key)),
                        observed(value),
                    );
                });
            };
        for method in module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Instance)
        {
            collect(&method.body, true, owner_fields);
        }
        crate::lower::for_each_emit_body_ref(app, &mut |body| collect(body, false, owner_fields));
        for class in app
            .library_classes
            .iter()
            .filter(|class| class.name == event.owner)
        {
            for method in class
                .methods
                .iter()
                .filter(|method| method.receiver == MethodReceiver::Class)
            {
                collect(&method.body, true, owner_fields);
            }
            for body in &class.unknown_calls {
                collect(body, true, owner_fields);
            }
        }
        for model in app.models.iter().filter(|model| model.name == event.owner) {
            for method in model
                .methods()
                .filter(|method| method.receiver == MethodReceiver::Class)
            {
                collect(&method.body, true, owner_fields);
            }
        }
    }
}
