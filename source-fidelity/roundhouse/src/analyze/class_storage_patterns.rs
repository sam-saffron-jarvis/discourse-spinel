//! Source-proven computed class storage used by cached definition templates.
//! Only types/addresses are retained; the original reflective operations still
//! execute against the actual method receiver, including unset/nil state.
use crate::App;
use crate::ClassId;
use crate::Symbol;
use crate::app::RuntimeClassStoragePattern;
use crate::dialect::MethodReceiver;
use crate::expr::{Expr, ExprNode, InterpPart, LValue, Literal};
use crate::ty::Ty;
use std::collections::BTreeMap;

fn walk(expr: &Expr, f: &mut impl FnMut(&Expr)) {
    f(expr);
    expr.node.for_each_child(&mut |child| walk(child, f));
}
pub(crate) fn address(expr: &Expr) -> Option<(String, String)> {
    let ExprNode::StringInterp { parts } = &*expr.node else {
        return None;
    };
    let [
        InterpPart::Text { value: prefix },
        InterpPart::Expr { expr: key },
        InterpPart::Text { value: suffix },
    ] = parts.as_slice()
    else {
        return None;
    };
    if !prefix.starts_with('@')
        || suffix.is_empty()
        || !key.ty.as_ref().is_some_and(Ty::is_stringish)
    {
        return None;
    }
    Some((prefix.clone(), suffix.clone()))
}

fn local_receiver(recv: Option<&Expr>, owner: &ClassId) -> bool {
    recv.is_none_or(|recv| match &*recv.node {
        ExprNode::SelfRef => recv.ty.as_ref().is_some_and(|ty| match ty {
            Ty::Class { id, args } if id.0.as_str() == "Class" => {
                matches!(args.as_slice(), [Ty::Class { id, .. }] if id == owner)
            }
            Ty::Class { id, .. } => id == owner,
            _ => false,
        }),
        ExprNode::Const { path } => {
            path.iter()
                .map(Symbol::as_str)
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join("::")
                == owner.0.as_str()
        }
        _ => false,
    })
}

/// The first analysis already knows every cache writer's closed value type,
/// even though its paired read is unknown. A second ordinary analysis consumes
/// that source contract before family admission. Any unbounded/unknown writer
/// keeps the original refusal. One address pattern per owner is intentional;
/// overlapping pattern algebra is not implied by this small cache capability.
pub(crate) fn prepare(app: &mut App, target: crate::build_target::BuildTarget) -> bool {
    use crate::build_target::BuildTarget::*;
    if !matches!(target, Ruby | Jruby | Spinel) || !app.runtime_class_storage_patterns.is_empty() {
        return false;
    }
    let mut contracts = Vec::new();
    for class in &app.library_classes {
        if class.is_module || class.parent.is_some() || class.origin.is_some() {
            continue;
        }
        let bodies: Vec<_> = class
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Class)
            .flat_map(|method| {
                std::iter::once(&method.body).chain(
                    method
                        .params
                        .iter()
                        .filter_map(|param| param.default.as_ref()),
                )
            })
            .chain(class.class_ivar_initializers.iter())
            .chain(class.unknown_calls.iter())
            .chain(class.constants.iter().map(|(_, value)| value))
            .collect();
        let mut producer = false;
        for body in &bodies {
            walk(body, &mut |expr| {
                if let ExprNode::Send { recv, method, .. } = &*expr.node {
                    producer |= method.as_str() == "define_singleton_method"
                        && local_receiver(recv.as_ref(), &class.name);
                }
            });
        }
        if !producer {
            continue;
        }
        let mut patterns = BTreeMap::<(String, String), Ty>::new();
        let mut valid = true;
        for body in &bodies {
            walk(body, &mut |expr| {
                if let ExprNode::Send {
                    recv, method, args, ..
                } = &*expr.node
                    && method.as_str() == "instance_variable_set"
                    && local_receiver(recv.as_ref(), &class.name)
                {
                    let [name, value] = args.as_slice() else {
                        valid = false;
                        return;
                    };
                    if let Some(pattern) = address(name) {
                        let Some(ty) = value.ty.as_ref().filter(|ty| !ty.mentions_unknown()) else {
                            valid = false;
                            return;
                        };
                        let prior = patterns.remove(&pattern).unwrap_or(Ty::Nil);
                        patterns.insert(pattern, crate::analyze::union_of(prior, ty.clone()));
                    } else if !matches!(
                        &*name.node,
                        ExprNode::Lit {
                            value: Literal::Str { .. } | Literal::Sym { .. }
                        }
                    ) {
                        valid = false;
                    }
                }
            });
        }
        if !valid || patterns.len() != 1 {
            continue;
        }
        let ((prefix, suffix), mut ty) = patterns.into_iter().next().unwrap();
        // Literal writes into that same namespace must also be accounted for.
        // Unknown explicit external writes could alias any member and refuse it.
        crate::lower::for_each_emit_body_ref(app, &mut |expr| {
            walk(expr, &mut |expr| {
                let (field, value) = match &*expr.node {
                    ExprNode::Send {
                        recv: Some(recv),
                        method,
                        args,
                        ..
                    } if method.as_str() == "instance_variable_set"
                        && local_receiver(Some(recv), &class.name) =>
                    {
                        let [name, value] = args.as_slice() else {
                            valid = false;
                            return;
                        };
                        match &*name.node {
                            ExprNode::Lit {
                                value: Literal::Str { value: field },
                            } => (Some(field.as_str()), Some(value)),
                            ExprNode::Lit {
                                value: Literal::Sym { value: field },
                            } => (Some(field.as_str()), Some(value)),
                            _ if address(name) == Some((prefix.clone(), suffix.clone())) => {
                                (None, Some(value))
                            }
                            _ => {
                                valid = false;
                                return;
                            }
                        }
                    }
                    _ => return,
                };
                if field.is_none_or(|field| field.starts_with(&prefix) && field.ends_with(&suffix))
                {
                    if let Some(value_ty) = value
                        .and_then(|value| value.ty.as_ref())
                        .filter(|ty| !ty.mentions_unknown())
                    {
                        ty = crate::analyze::union_of(ty.clone(), value_ty.clone());
                    } else {
                        valid = false;
                    }
                }
            })
        });
        // Ordinary @literal assignments in this class are writers too.
        for body in &bodies {
            walk(body, &mut |expr| {
                if let ExprNode::OpAssign {
                    target: LValue::Ivar { name },
                    ..
                } = &*expr.node
                {
                    let name = format!("@{name}");
                    if name.starts_with(&prefix) && name.ends_with(&suffix) {
                        valid = false;
                    }
                }
                if let ExprNode::MultiAssign { targets, .. } = &*expr.node {
                    for target in targets {
                        if let LValue::Ivar { name } = target {
                            let name = format!("@{name}");
                            if name.starts_with(&prefix) && name.ends_with(&suffix) {
                                valid = false;
                            }
                        }
                    }
                }
                let (name, value) = match &*expr.node {
                    ExprNode::Assign {
                        target: LValue::Ivar { name },
                        value,
                    } => (format!("@{name}"), value),
                    ExprNode::Send {
                        recv, method, args, ..
                    } if method.as_str() == "instance_variable_set"
                        && local_receiver(recv.as_ref(), &class.name) =>
                    {
                        let [name, value] = args.as_slice() else {
                            valid = false;
                            return;
                        };
                        let name = match &*name.node {
                            ExprNode::Lit {
                                value: Literal::Str { value },
                            } => value.clone(),
                            ExprNode::Lit {
                                value: Literal::Sym { value },
                            } => value.to_string(),
                            _ => return,
                        };
                        (name, value)
                    }
                    _ => return,
                };
                if name.starts_with(&prefix) && name.ends_with(&suffix) {
                    if let Some(value_ty) = value.ty.as_ref().filter(|ty| !ty.mentions_unknown()) {
                        ty = crate::analyze::union_of(ty.clone(), value_ty.clone());
                    } else {
                        valid = false;
                    }
                }
            });
        }
        if valid {
            contracts.push(RuntimeClassStoragePattern {
                owner: class.name.clone(),
                prefix,
                suffix,
                value: ty,
            });
        }
    }
    let changed = !contracts.is_empty();
    app.runtime_class_storage_patterns = contracts;
    changed
}
