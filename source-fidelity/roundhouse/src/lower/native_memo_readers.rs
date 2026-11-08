//! Preserve the finite core class_eval memo-reader producer for native Ruby.
//!
//! The native compiler already implements this exact declaration form. Keep
//! the original loop (including duplicate names, source order and lazy per-
//! instance storage), not synthesized getters or eagerly allocated arrays.
//! Unknown strings, extra statements, hooks/overrides and inherited worlds
//! remain unadmitted. This does NOT admit File.read/instance_eval activation.
use crate::App;
use crate::dialect::MethodReceiver;
use crate::expr::{Expr, ExprNode, InterpPart, LValue, Literal};

pub fn apply(app: &mut App) {
    // These core protocols control the literal loop/interpolation/definition.
    if app.library_classes.iter().any(|c| {
        matches!(
            c.name.0.as_str(),
            "Object" | "BasicObject" | "Class" | "Module" | "Symbol" | "String" | "Array"
        )
    }) {
        return;
    }
    for class in &mut app.library_classes {
        if class.origin.is_some()
            || class.is_module
            || class.parent.is_some()
            || !class.includes.is_empty()
            || class.methods.iter().any(|m| {
                m.receiver == MethodReceiver::Class
                    && matches!(
                        m.name.as_str(),
                        "class_eval" | "method_added" | "singleton_method_added"
                    )
            })
        {
            continue;
        }
        let Some(groups) = class
            .unknown_calls
            .iter()
            .map(admitted)
            .collect::<Option<Vec<_>>>()
        else {
            continue;
        };
        let names: Vec<_> = groups.into_iter().flatten().collect();
        if !class.constants.is_empty()
            || !class.class_ivar_initializers.is_empty()
            || !class.conditional_definitions.is_empty()
            || class.methods.iter().any(|m| {
                names.iter().any(|name| {
                    m.name.as_str() == name
                        || m.name.as_str().strip_suffix('=') == Some(name.as_str())
                }) || writes(&m.body, &names)
            })
        {
            continue;
        }
        for expression in &mut class.unknown_calls {
            if expression.decisions & crate::expr::SINGLETON_BODY == 0 {
                expression.decisions |= crate::expr::REPLAYED_CLASS_BODY;
            }
        }
    }
}
fn single(expr: &Expr) -> &Expr {
    match &*expr.node {
        ExprNode::Seq { exprs } if exprs.len() == 1 => single(&exprs[0]),
        _ => expr,
    }
}
fn identifier(value: &str) -> bool {
    let mut bytes = value.bytes();
    matches!(bytes.next(), Some(b'a'..=b'z' | b'_'))
        && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
}
fn writes(expr: &Expr, names: &[String]) -> bool {
    let direct = matches!(&*expr.node,
        ExprNode::Assign { target: LValue::Ivar { name }, .. }
        | ExprNode::OpAssign { target: LValue::Ivar { name }, .. }
        if names.iter().any(|n| n==name.as_str()));
    let mut found = direct;
    expr.node
        .for_each_child(&mut |child| found |= writes(child, names));
    found
}
fn admitted(expression: &Expr) -> Option<Vec<String>> {
    let ExprNode::Send {
        recv: Some(receiver),
        method,
        args,
        block: Some(block),
        ..
    } = &*expression.node
    else {
        return None;
    };
    if method.as_str() != "each" || !args.is_empty() {
        return None;
    }
    let ExprNode::Array { elements, .. } = &*receiver.node else {
        return None;
    };
    if elements.is_empty() || elements.len() > 128 {
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
    if params.len() != 1 || !extra_params.is_empty() {
        return None;
    }
    let ExprNode::Send {
        recv,
        method,
        args,
        block: None,
        ..
    } = &*single(body).node
    else {
        return None;
    };
    if method.as_str() != "class_eval" || recv.is_some() || args.len() != 1 {
        return None;
    }
    let ExprNode::StringInterp { parts } = &*args[0].node else {
        return None;
    };
    let mut names = Vec::new();
    for element in elements {
        let name = match &*element.node {
            ExprNode::Lit {
                value: Literal::Sym { value },
            } => value.as_str(),
            ExprNode::Lit {
                value: Literal::Str { value },
            } => value.as_str(),
            _ => return None,
        };
        if !identifier(name) {
            return None;
        }
        let mut rendered = String::new();
        for part in parts {
            match part {
                InterpPart::Text { value } => rendered.push_str(value),
                InterpPart::Expr { expr } if matches!(&*expr.node, ExprNode::Var { name, .. } if name==&params[0]) => {
                    rendered.push_str(name)
                }
                _ => return None,
            }
        }
        // Require the exact rendered AST. The general library walk consumes
        // visibility/alias declarations, which are not part of this admission
        // even if the resulting getter happens to have the right body.
        let parsed = ruby_prism::parse(rendered.as_bytes());
        if parsed.errors().next().is_some() {
            return None;
        }
        let root = parsed.node();
        let program = root.as_program_node()?;
        let statements: Vec<_> = program.statements().body().iter().collect();
        if statements.len() != 1 || statements[0].as_def_node().is_none() {
            return None;
        }
        let method = statements[0].as_def_node()?;
        if method.receiver().is_some()
            || method.parameters().is_some()
            || method.name().as_slice() != name.as_bytes()
        {
            return None;
        }
        let body = method.body()?;
        let statements = body.as_statements_node()?;
        let statements: Vec<_> = statements.body().iter().collect();
        if statements.len() != 1 {
            return None;
        }
        let write = statements[0].as_instance_variable_or_write_node()?;
        if write.name().as_slice() != format!("@{name}").as_bytes()
            || !write.value().as_array_node()?.elements().is_empty()
        {
            return None;
        }
        names.push(name.to_string());
    }
    Some(names)
}
