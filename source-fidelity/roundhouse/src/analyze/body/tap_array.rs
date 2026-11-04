//! Source-owned empty-array tap accumulation (Plugin::Instance.find_all).
//! The block's return is discarded: only writes to its unchanged receiver
//! parameter constrain the receiver's element type. No runtime value is read.
use super::{Expr, ExprNode, LValue, Symbol, Ty};

pub(super) fn overridden(classes: &crate::det::HashMap<crate::ClassId, super::ClassInfo>) -> bool {
    let mut pending: Vec<_> = ["Array", "Object", "Kernel", "BasicObject"]
        .into_iter()
        .map(|name| crate::ClassId(Symbol::from(name)))
        .collect();
    let mut seen = std::collections::BTreeSet::new();
    while let Some(owner) = pending.pop() {
        if !seen.insert(owner.clone()) {
            continue;
        }
        let Some(class) = classes.get(&owner) else {
            continue;
        };
        if class.source_instance_methods.contains(&Symbol::from("tap")) {
            return true;
        }
        pending.extend(class.includes.iter().chain(class.parent.iter()).cloned());
    }
    false
}

pub(super) fn result(receiver: &Expr, block: &Expr) -> Option<Ty> {
    if !matches!(&*receiver.node, ExprNode::Array { elements, .. } if elements.is_empty()) {
        return None;
    }
    let ExprNode::Lambda {
        params,
        rest_param: None,
        extra_params,
        block_param: None,
        body,
        ..
    } = &*block.node
    else {
        return None;
    };
    let [parameter] = params.as_slice() else {
        return None;
    };
    if !extra_params.is_empty() || super::bytes_block_has_escaping_break(body) {
        return None;
    }
    let mut values = Vec::new();
    let valid = writes(body, parameter, &mut values);
    let element = if valid {
        values
            .into_iter()
            .reduce(super::union_of)
            .unwrap_or(Ty::Var {
                var: crate::ident::TyVar(0),
            })
    } else {
        Ty::Untyped
    };
    Some(Ty::Array {
        elem: std::sync::Arc::new(element),
    })
}

fn names(expr: &Expr, parameter: &Symbol) -> bool {
    if let ExprNode::Lambda { params, .. } = &*expr.node
        && params.contains(parameter)
    {
        return false;
    }
    if matches!(&*expr.node, ExprNode::Var { name, .. } if name == parameter) {
        return true;
    }
    let mut found = false;
    expr.node
        .for_each_child(&mut |child| found |= names(child, parameter));
    found
}

fn writes(expr: &Expr, parameter: &Symbol, values: &mut Vec<Ty>) -> bool {
    match &*expr.node {
        ExprNode::Lambda { params, .. } if params.contains(parameter) => return true,
        ExprNode::Assign {
            target: LValue::Var { name, .. },
            ..
        }
        | ExprNode::OpAssign {
            target: LValue::Var { name, .. },
            ..
        } if name == parameter => return false,
        ExprNode::Assign { value, .. } | ExprNode::OpAssign { value, .. }
            if names(value, parameter) =>
        {
            return false;
        }
        ExprNode::Let { name, .. } if name == parameter => return false,
        ExprNode::MultiAssign { .. } | ExprNode::Return { .. } => return false,
        ExprNode::Array { .. } | ExprNode::Hash { .. } if names(expr, parameter) => return false,
        ExprNode::Send {
            recv: Some(receiver),
            method,
            args,
            block,
            ..
        } if matches!(&*receiver.node, ExprNode::Var { name, .. } if name == parameter) => {
            if block.is_some() || args.iter().any(|arg| names(arg, parameter)) {
                return false;
            }
            match method.as_str() {
                "<<" if args.len() == 1 => {
                    values.push(
                        args[0]
                            .ty
                            .clone()
                            .filter(|ty| !ty.mentions_unknown())
                            .unwrap_or(Ty::Untyped),
                    );
                }
                "push" | "append" | "unshift" | "prepend" if !args.is_empty() => {
                    for arg in args {
                        values.push(if matches!(&*arg.node, ExprNode::Splat { .. }) {
                            Ty::Untyped
                        } else {
                            arg.ty
                                .clone()
                                .filter(|ty| !ty.mentions_unknown())
                                .unwrap_or(Ty::Untyped)
                        });
                    }
                }
                "size" | "length" | "empty?" | "clear" if args.is_empty() => {}
                _ => return false,
            }
            return args.iter().all(|arg| writes(arg, parameter, values));
        }
        ExprNode::Send { args, .. } if args.iter().any(|arg| names(arg, parameter)) => {
            return false;
        }
        _ => {}
    }
    let mut valid = true;
    expr.node
        .for_each_child(&mut |child| valid &= writes(child, parameter, values));
    valid
}
