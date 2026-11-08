//! One-argument JSON.load_file is the stdlib's UTF-8 read followed by parse.
//! Keep options/blocks/unknown paths and source core overrides unclaimed.
//! This is a composition of existing file/JSON primitives, not a parsed-data
//! snapshot; the live file, read/parse failures and operand effects remain.
use crate::App;
use crate::expr::{Expr, ExprNode, Literal};
use crate::ident::{ClassId, Symbol};
use crate::ty::Ty;

pub fn apply(app: &mut App) {
    let overrides = |name: &str| {
        let name = name.rsplit("::").next().unwrap_or(name);
        matches!(
            name,
            "JSON" | "File" | "Encoding" | "Object" | "BasicObject" | "Module" | "Class"
        )
    };
    if app
        .library_classes
        .iter()
        .any(|class| overrides(class.name.0.as_str()))
        || app
            .models
            .iter()
            .any(|model| overrides(model.name.0.as_str()))
    {
        return;
    }
    super::for_each_hook_body(app, &mut rewrite);
    for view in &mut app.views {
        rewrite(&mut view.body);
    }
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
    if method.as_str() != "load_file"
        || args.len() != 1
        || args[0].ty != Some(Ty::Str)
        || !matches!(receiver.ty.as_ref(), Some(Ty::Class { id, .. }) if id.0.as_str()=="JSON")
        || !matches!(&*receiver.node, ExprNode::Const { path } if path.len()==1 && path[0].as_str()=="JSON")
    {
        return;
    }
    let mut file = Expr::new(
        expr.span,
        ExprNode::Const {
            path: vec![Symbol::from(""), Symbol::from("File")],
        },
    );
    file.ty = Some(Ty::Class {
        id: ClassId(Symbol::from("File")),
        args: Default::default(),
    });
    let mut key = Expr::new(
        expr.span,
        ExprNode::Lit {
            value: Literal::Sym {
                value: Symbol::from("encoding"),
            },
        },
    );
    key.ty = Some(Ty::Sym);
    let mut encoding = Expr::new(
        expr.span,
        ExprNode::Lit {
            value: Literal::Str {
                value: "UTF-8".into(),
            },
        },
    );
    encoding.ty = Some(Ty::Str);
    let mut options = Expr::new(
        expr.span,
        ExprNode::Hash {
            entries: vec![(key, encoding)],
            kwargs: true,
        },
    );
    options.ty = Some(Ty::Hash {
        key: std::sync::Arc::new(Ty::Sym),
        value: std::sync::Arc::new(Ty::Str),
    });
    let mut read = Expr::new(
        expr.span,
        ExprNode::Send {
            recv: Some(file),
            method: Symbol::from("read"),
            args: vec![args[0].clone(), options],
            block: None,
            parenthesized: true,
        },
    );
    read.ty = Some(Ty::Str);
    *expr.node = ExprNode::Send {
        recv: Some(receiver.clone()),
        method: Symbol::from("parse"),
        args: vec![read],
        block: None,
        parenthesized: true,
    };
    expr.ty = Some(Ty::Untyped);
}
