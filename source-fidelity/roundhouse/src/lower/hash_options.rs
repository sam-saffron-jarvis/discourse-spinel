//! ActiveSupport Hash#assert_valid_keys with statically flat key arguments.
//!
//! The receiver and every argument still execute once, left to right. Unknown
//! receivers, nested/dynamic splats, blocks and source core overrides retain the
//! original send. The helper reads live keys and raises on the first invalid one;
//! it neither filters options nor copies/mutates the input hash.
use crate::App;
use crate::expr::{Expr, ExprNode};
use crate::ident::{ClassId, Symbol};
use crate::ty::Ty;

pub fn apply(app: &mut App) {
    if app
        .library_classes
        .iter()
        .any(|c| c.name.0.as_str() == "Hash")
    {
        return;
    }
    super::for_each_hook_body(app, &mut rewrite);
    for view in &mut app.views {
        rewrite(&mut view.body);
    }
}
fn scalar(ty: &Ty) -> bool {
    match ty {
        Ty::Str | Ty::Sym | Ty::Int | Ty::Float | Ty::Bool | Ty::Nil => true,
        Ty::Union { variants } => !variants.is_empty() && variants.iter().all(scalar),
        _ => false,
    }
}
// Do not turn a pre-existing inference gap into a falsely precise bang-call
// result. Different/new key or value types need alias-aware mutation inference.
fn covers(left: &Ty, right: &Ty) -> bool {
    if left.mentions_unknown() {
        return true;
    }
    if right.mentions_unknown() {
        return false;
    }
    if left == right {
        return true;
    }
    match (left, right) {
        (_, Ty::Union { variants }) => variants.iter().all(|r| covers(left, r)),
        (Ty::Union { variants }, _) => variants.iter().any(|l| covers(l, right)),
        _ => false,
    }
}
fn compatible(left: &Ty, right: &Ty) -> bool {
    matches!((left, right), (Ty::Hash { key, value }, Ty::Hash { key: other_key, value: other_value })
        if covers(key, other_key) && covers(value, other_value))
}

fn rewrite(expr: &mut Expr) {
    expr.node.for_each_child_mut(&mut rewrite);
    let ExprNode::Send {
        recv: Some(receiver),
        method,
        args,
        block: None,
        ..
    } = &*expr.node
    else {
        return;
    };
    if !matches!(receiver.ty, Some(Ty::Hash { .. })) {
        return;
    }
    if method.as_str() == "reverse_merge!"
        && args.len() == 1
        && args[0]
            .ty
            .as_ref()
            .is_some_and(|other| compatible(receiver.ty.as_ref().unwrap(), other))
    {
        let mut defaults = args[0].clone();
        if let ExprNode::Hash { kwargs, .. } = &mut *defaults.node {
            *kwargs = false;
        }
        let values = vec![receiver.clone(), defaults];
        let result_ty = receiver.ty.clone();
        runtime_call(expr, "reverse_merge!", values, result_ty);
        return;
    }
    if method.as_str() != "assert_valid_keys" {
        return;
    }
    let keys = if args.len() == 1
        && matches!(args[0].ty.as_ref(), Some(Ty::Array { elem }) if scalar(elem))
    {
        args[0].clone()
    } else if args.iter().all(|a| a.ty.as_ref().is_some_and(scalar)) {
        let mut array = Expr::new(
            expr.span,
            ExprNode::Array {
                elements: args.clone(),
                style: Default::default(),
            },
        );
        let mut types = Vec::new();
        for ty in args.iter().filter_map(|a| a.ty.clone()) {
            if !types.contains(&ty) {
                types.push(ty);
            }
        }
        let elem = match types.len() {
            0 => Ty::Bottom,
            1 => types.remove(0),
            _ => Ty::Union {
                variants: types.into(),
            },
        };
        array.ty = Some(Ty::Array {
            elem: std::sync::Arc::new(elem),
        });
        array
    } else {
        return;
    };
    let result_ty = receiver.ty.clone();
    let arguments = vec![receiver.clone(), keys];
    runtime_call(expr, "assert_valid_keys", arguments, result_ty);
}
fn runtime_call(expr: &mut Expr, method: &str, arguments: Vec<Expr>, result_ty: Option<Ty>) {
    let mut namespace = Expr::new(
        expr.span,
        ExprNode::Const {
            path: vec![Symbol::from("ActiveSupport")],
        },
    );
    namespace.ty = Some(Ty::Class {
        id: ClassId(Symbol::from("ActiveSupport")),
        args: Default::default(),
    });
    *expr.node = ExprNode::Send {
        recv: Some(namespace),
        method: Symbol::from(method),
        args: arguments,
        block: None,
        parenthesized: true,
    };
    expr.ty = result_ty;
}
