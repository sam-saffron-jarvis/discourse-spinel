//! Rebuild source singleton memoized Hash slots from actual writers. Empty
//! literal annotations from a prior typing round are not stored-value evidence.
use crate::det::HashMap;
use crate::dialect::MethodReceiver;
use crate::expr::{Expr, ExprNode, LValue, Literal, OpAssignOp};
use crate::ty::Ty;
use crate::{App, ClassId, Symbol};
use std::collections::BTreeSet;
use std::sync::Arc;

fn pending_hash() -> Ty {
    Ty::Hash {
        key: Arc::new(Ty::Var {
            var: crate::ident::TyVar(0),
        }),
        value: Arc::new(Ty::Var {
            var: crate::ident::TyVar(0),
        }),
    }
}
fn same_receiver(receiver: Option<&Expr>) -> bool {
    receiver.is_none_or(|receiver| matches!(&*receiver.node, ExprNode::SelfRef))
}
fn literal_field(expr: &Expr) -> Option<Symbol> {
    let text = match &*expr.node {
        ExprNode::Lit {
            value: Literal::Sym { value },
        } => value.as_str(),
        ExprNode::Lit {
            value: Literal::Str { value },
        } => value,
        _ => return None,
    };
    text.strip_prefix('@').map(Symbol::from)
}

pub(super) fn collect(app: &App, fields: &mut HashMap<ClassId, HashMap<Symbol, Ty>>) {
    for class in app
        .library_classes
        .iter()
        .filter(|class| class.origin.is_none())
    {
        if app
            .library_classes
            .iter()
            .filter(|other| other.name == class.name)
            .count()
            != 1
        {
            continue;
        }
        let names: BTreeSet<_> = class.methods.iter().filter(|method| method.receiver == MethodReceiver::Class && method.params.is_empty() && method.block_param.is_none()
            && !app.rbs_signatures.get(&class.name).is_some_and(|methods| methods.contains_key(&method.name)))
            .filter_map(|method| match &*method.body.node {
                ExprNode::OpAssign { target: LValue::Ivar { name }, op: OpAssignOp::OrOr, value }
                    if matches!(&*value.node, ExprNode::Hash { entries, .. } if entries.is_empty()) => Some(name.clone()),
                _ => None,
            }).collect();
        if names.is_empty() {
            continue;
        }
        let mut fresh: HashMap<_, _> = names
            .iter()
            .map(|name| (name.clone(), pending_hash()))
            .collect();
        let mut opaque = BTreeSet::new();
        fn value_write(
            name: &Symbol,
            value: &Expr,
            fresh: &mut HashMap<Symbol, Ty>,
            opaque: &mut BTreeSet<Symbol>,
        ) {
            if matches!(&*value.node, ExprNode::Hash { entries, .. } if entries.is_empty()) {
                return;
            }
            let ty = value.ty.clone().unwrap_or(Ty::Untyped);
            if !matches!(ty.peel_nilable(), Ty::Hash { .. } | Ty::Nil) {
                opaque.insert(name.clone());
                return;
            }
            let previous = fresh.remove(name).unwrap_or_else(pending_hash);
            fresh.insert(name.clone(), super::body::join_ivar_slot(previous, ty));
        }
        fn visit(
            expr: &Expr,
            names: &BTreeSet<Symbol>,
            fresh: &mut HashMap<Symbol, Ty>,
            opaque: &mut BTreeSet<Symbol>,
        ) {
            if expr.nested_def().is_some() {
                return;
            }
            // A field handed to another local/call/return can be mutated
            // through that alias. Only direct indexed access and the known
            // read-only receiver operations below are closed observations.
            if let ExprNode::Ivar { name } = &*expr.node {
                if names.contains(name) {
                    opaque.insert(name.clone());
                }
                return;
            }
            match &*expr.node {
                ExprNode::Assign {
                    target: LValue::Ivar { name },
                    value,
                }
                | ExprNode::OpAssign {
                    target: LValue::Ivar { name },
                    value,
                    ..
                } if names.contains(name) => value_write(name, value, fresh, opaque),
                ExprNode::Send {
                    recv, method, args, ..
                } if same_receiver(recv.as_ref()) && method.as_str() == "instance_variable_set" => {
                    if let [name, value] = args.as_slice() {
                        if let Some(name) = literal_field(name) {
                            if names.contains(&name) {
                                value_write(&name, value, fresh, opaque);
                            }
                        } else {
                            opaque.extend(names.iter().cloned());
                        }
                    } else {
                        opaque.extend(names.iter().cloned());
                    }
                }
                ExprNode::Send {
                    recv, method, args, ..
                } if same_receiver(recv.as_ref())
                    && matches!(method.as_str(), "send" | "__send__" | "public_send") =>
                {
                    let target = args.first().and_then(|arg| match &*arg.node {
                        ExprNode::Lit {
                            value: Literal::Sym { value },
                        } => Some(value.as_str()),
                        ExprNode::Lit {
                            value: Literal::Str { value },
                        } => Some(value.as_str()),
                        _ => None,
                    });
                    if target.is_none_or(|name| name == "instance_variable_set") {
                        opaque.extend(names.iter().cloned());
                    }
                }
                ExprNode::Send {
                    method,
                    block: Some(_),
                    ..
                } if matches!(
                    method.as_str(),
                    "instance_eval"
                        | "instance_exec"
                        | "class_eval"
                        | "class_exec"
                        | "module_eval"
                        | "module_exec"
                ) =>
                {
                    opaque.extend(names.iter().cloned());
                    return;
                }
                _ => {}
            }
            if let ExprNode::Send {
                recv: Some(receiver),
                method,
                ..
            } = &*expr.node
                && let ExprNode::Ivar { name } = &*receiver.node
                && names.contains(name)
                && !matches!(
                    method.as_str(),
                    "[]="
                        | "[]"
                        | "fetch"
                        | "key?"
                        | "has_key?"
                        | "include?"
                        | "size"
                        | "length"
                        | "empty?"
                        | "keys"
                        | "values"
                        | "each"
                        | "each_key"
                        | "each_value"
                        | "clear"
                )
            {
                opaque.insert(name.clone());
            }
            let indexed = match &*expr.node {
                ExprNode::Send {
                    recv: Some(receiver),
                    method,
                    args,
                    block: None,
                    ..
                } if method.as_str() == "[]=" && args.len() == 2 => {
                    Some((receiver, &args[0], &args[1]))
                }
                ExprNode::Assign {
                    target: LValue::Index { recv, index },
                    value,
                }
                | ExprNode::OpAssign {
                    target: LValue::Index { recv, index },
                    value,
                    ..
                } => Some((recv, index, value)),
                _ => None,
            };
            if let Some((receiver, key, value)) = indexed
                && let ExprNode::Ivar { name } = &*receiver.node
                && names.contains(name)
            {
                let observed = |expr: &Expr| {
                    expr.ty
                        .clone()
                        .filter(|ty| !ty.mentions_unknown())
                        .unwrap_or(Ty::Untyped)
                };
                super::widen_hash_ivar_value(fresh, name, Some(observed(key)), observed(value));
            }
            let receiver = match &*expr.node {
                ExprNode::Send {
                    recv: Some(receiver),
                    ..
                } => Some(receiver),
                ExprNode::Assign {
                    target: LValue::Index { recv, .. },
                    ..
                }
                | ExprNode::OpAssign {
                    target: LValue::Index { recv, .. },
                    ..
                } => Some(recv),
                _ => None,
            };
            expr.node.for_each_child(&mut |child| {
                if receiver.is_some_and(|receiver| std::ptr::eq(receiver, child))
                    && matches!(&*child.node, ExprNode::Ivar { .. })
                {
                    return;
                }
                visit(child, names, fresh, opaque);
            });
        }
        for body in class
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Class)
            .map(|method| &method.body)
            .chain(class.class_ivar_initializers.iter())
            .chain(class.unknown_calls.iter())
        {
            visit(body, &names, &mut fresh, &mut opaque);
        }
        let target = fields.entry(class.name.clone()).or_default();
        for (name, value) in fresh {
            target.insert(
                name.clone(),
                if opaque.contains(&name) {
                    Ty::Untyped
                } else {
                    value
                },
            );
        }
    }
}
