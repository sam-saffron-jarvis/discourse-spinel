//! Opt-in, guarded construction-context partial evaluation. No application names.
//!
//! The only supported world is a source-indexed leaf constructed with nils.
//! Constructor parameter guards enforce that domain even for an unseen caller.
//! Mutable/reflected worlds are declined. `false_expr && rhs` becomes
//! `false_expr && raise(context_error)`: the SAME left expression executes once,
//! retaining its identity/effects and explicitly refusing a violated runtime fact.
use crate::dialect::{LibraryClass, MethodDef, MethodReceiver};
use crate::expr::{BoolOpKind, Expr, ExprNode, LValue, Literal};
use crate::span::Span;
use crate::{App, Symbol};
use ruby_prism::Visit;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone)]
pub struct RootSource {
    pub path: String,
    pub text: String,
}
#[derive(Default, Serialize)]
pub struct Report {
    pub scope: String,
    pub roots: Vec<String>,
    pub refusals: Vec<String>,
    pub contexts: Vec<Context>,
    pub rewrites: Vec<Rewrite>,
    pub assumptions: Vec<String>,
    pub ruby_sources: Vec<String>,
    pub source_catalogue: Vec<String>,
}
#[derive(Serialize)]
pub struct Context {
    pub class: String,
    pub constructor: Span,
    pub nil_parameters: Vec<String>,
    pub fields: Vec<String>,
}
#[derive(Serialize)]
pub struct Rewrite {
    pub owner: String,
    pub method: String,
    pub expression: Span,
    pub retained_left: Span,
    pub result: String,
    pub witnesses: Vec<Span>,
}
#[derive(Clone, Debug)]
enum Value {
    Nil,
    Bool(bool),
    Object(String, BTreeMap<String, Value>),
}
impl Value {
    fn truthy(&self) -> bool {
        !matches!(self, Self::Nil | Self::Bool(false))
    }
}

const MUTABLE: &[&str] = &[
    "eval",
    "class_eval",
    "class_exec",
    "module_eval",
    "module_exec",
    "instance_eval",
    "instance_exec",
    "instance_variable_set",
    "remove_instance_variable",
    "class_variable_set",
    "const_set",
    "const_get",
    "remove_const",
    "define_method",
    "define_singleton_method",
    "remove_method",
    "undef_method",
    "alias_method",
    "prepend",
    "extend",
    "send",
    "__send__",
    "public_send",
    "singleton_class",
    "method",
    "public_method",
    "instance_method",
    "allocate",
    "load",
    "autoload",
    "set_trace_func",
];
fn constant(node: &ruby_prism::Node<'_>) -> Option<String> {
    if let Some(n) = node.as_constant_read_node() {
        return Some(String::from_utf8_lossy(n.name().as_slice()).into_owned());
    }
    let n = node.as_constant_path_node()?;
    let name = String::from_utf8_lossy(n.name()?.as_slice()).into_owned();
    Some(match n.parent() {
        Some(parent) => format!("{}::{name}", constant(&parent)?),
        None => name,
    })
}
struct World<'a> {
    classes: &'a BTreeSet<String>,
    extra: bool,
    bad: Vec<String>,
    constructors: BTreeMap<String, Vec<bool>>,
    includes: BTreeMap<String, usize>,
}
impl<'pr> Visit<'pr> for World<'_> {
    fn visit_call_node(&mut self, node: &ruby_prism::CallNode<'pr>) {
        let name = String::from_utf8_lossy(node.name().as_slice()).into_owned();
        let static_extend = !self.extra
            && name == "extend"
            && node.receiver().is_none()
            && node
                .arguments()
                .is_some_and(|a| a.arguments().iter().all(|a| constant(&a).is_some()));
        if (MUTABLE.contains(&name.as_str()) && !static_extend) || (self.extra && name == "include")
        {
            self.bad
                .push(format!("unproved mutable/reflected world: {name}"));
        }
        if name == "include" {
            if let Some(arguments) = node.arguments() {
                for argument in arguments.arguments().iter() {
                    if let Some(module) = constant(&argument) {
                        *self.includes.entry(module).or_default() += 1;
                    } else {
                        self.bad.push("unproved dynamic module inclusion".into());
                    }
                }
            }
        }
        if name == "new" {
            if let Some(owner) = node.receiver().as_ref().and_then(constant) {
                let nils = node
                    .arguments()
                    .is_none_or(|a| a.arguments().iter().all(|a| a.as_nil_node().is_some()));
                self.constructors.entry(owner).or_default().push(nils);
            }
        }
        if matches!(name.as_str(), "require" | "require_relative")
            && !node
                .arguments()
                .is_some_and(|a| a.arguments().iter().all(|n| n.as_string_node().is_some()))
        {
            self.bad.push("nonliteral source loading".into());
        }
        ruby_prism::visit_call_node(self, node);
    }
    fn visit_class_node(&mut self, node: &ruby_prism::ClassNode<'pr>) {
        if self.extra
            && (constant(&node.constant_path()).is_some_and(|n| {
                self.classes.contains(&n)
                    || matches!(n.as_str(), "Object" | "BasicObject" | "NilClass" | "Class")
            }) || node.superclass().is_some())
        {
            self.bad
                .push("extra root reopens/subclasses an unproved application world".into());
        }
        ruby_prism::visit_class_node(self, node);
    }
    fn visit_module_node(&mut self, node: &ruby_prism::ModuleNode<'pr>) {
        if self.extra && constant(&node.constant_path()).is_some_and(|n| self.classes.contains(&n))
        {
            self.bad
                .push("extra root reopens an application module".into());
        }
        ruby_prism::visit_module_node(self, node);
    }
    fn visit_constant_read_node(&mut self, node: &ruby_prism::ConstantReadNode<'pr>) {
        if matches!(node.name().as_slice(), b"TracePoint" | b"ObjectSpace") {
            self.bad.push("unproved tracing/object-space world".into());
        }
    }
}
struct Index {
    classes: BTreeMap<String, LibraryClass>,
    duplicates: BTreeSet<String>,
}
impl Index {
    fn method(&self, class: &str, name: &str, depth: usize) -> Option<(&str, &MethodDef)> {
        if depth > 20 || self.duplicates.contains(class) {
            return None;
        }
        let c = self.classes.get(class)?;
        if let Some(m) = c
            .methods
            .iter()
            .rev()
            .find(|m| m.receiver == MethodReceiver::Instance && m.name.as_str() == name)
        {
            return Some((c.name.0.as_str(), m));
        }
        for module in c.includes.iter().rev() {
            if let Some(m) = self.method(module.0.as_str(), name, depth + 1) {
                return Some(m);
            }
        }
        c.parent
            .as_ref()
            .and_then(|p| self.method(p.0.as_str(), name, depth + 1))
    }
    fn object(&self, name: &str, depth: usize, evidence: &mut Vec<Span>) -> Option<Value> {
        if depth > 20 || self.duplicates.contains(name) {
            return None;
        }
        let class = self.classes.get(name)?;
        if class.parent.is_some()
            || !class.unknown_calls.is_empty()
            || class.methods.iter().any(|m| {
                m.receiver == MethodReceiver::Class && matches!(m.name.as_str(), "new" | "allocate")
            })
        {
            return None;
        }
        let mut object = Value::Object(name.into(), BTreeMap::new());
        if let Some((_, init)) = self.method(name, "initialize", 0) {
            let mut env = BTreeMap::new();
            for p in &init.params {
                if p.keyword
                    || p.rest
                    || !matches!(
                        p.default.as_ref().map(|e| &*e.node),
                        Some(ExprNode::Lit {
                            value: Literal::Nil
                        })
                    )
                {
                    return None;
                }
                env.insert(p.name.to_string(), Value::Nil);
            }
            evidence.push(init.name_span);
            self.initialize(&init.body, &env, &mut object, depth + 1, evidence)?;
        }
        Some(object)
    }
    fn initialize(
        &self,
        expr: &Expr,
        env: &BTreeMap<String, Value>,
        object: &mut Value,
        depth: usize,
        evidence: &mut Vec<Span>,
    ) -> Option<()> {
        match &*expr.node {
            ExprNode::Seq { exprs } => {
                for e in exprs {
                    self.initialize(e, env, object, depth, evidence)?;
                }
                Some(())
            }
            ExprNode::Assign {
                target: LValue::Ivar { name },
                value,
            } => {
                let value = self.eval(value, env, object, depth + 1, evidence)?;
                let Value::Object(_, fields) = object else {
                    return None;
                };
                fields.insert(name.to_string(), value);
                Some(())
            }
            ExprNode::Lit {
                value: Literal::Nil,
            } => Some(()),
            _ => None,
        }
    }
    fn eval(
        &self,
        expr: &Expr,
        env: &BTreeMap<String, Value>,
        object: &Value,
        depth: usize,
        evidence: &mut Vec<Span>,
    ) -> Option<Value> {
        if depth > 30 || expr.nested_def().is_some() {
            return None;
        }
        match &*expr.node {
            ExprNode::Lit {
                value: Literal::Nil,
            } => Some(Value::Nil),
            ExprNode::Lit {
                value: Literal::Bool { value },
            } => Some(Value::Bool(*value)),
            ExprNode::Var { name, .. } => env.get(name.as_str()).cloned(),
            ExprNode::SelfRef => Some(object.clone()),
            ExprNode::Ivar { name } => match object {
                Value::Object(_, f) => f.get(name.as_str()).cloned(),
                _ => None,
            },
            ExprNode::Seq { exprs } => {
                let mut result = Value::Nil;
                for e in exprs {
                    result = self.eval(e, env, object, depth + 1, evidence)?;
                }
                Some(result)
            }
            ExprNode::BoolOp {
                op, left, right, ..
            } => {
                let value = self.eval(left, env, object, depth + 1, evidence)?;
                if matches!(op, BoolOpKind::And) != value.truthy() {
                    Some(value)
                } else {
                    self.eval(right, env, object, depth + 1, evidence)
                }
            }
            ExprNode::Send {
                recv: Some(recv),
                method,
                args,
                block: None,
                ..
            } if method.as_str() == "new" && args.is_empty() => {
                let ExprNode::Const { path } = &*recv.node else {
                    return None;
                };
                self.object(
                    &path
                        .iter()
                        .map(Symbol::as_str)
                        .filter(|s| !s.is_empty())
                        .collect::<Vec<_>>()
                        .join("::"),
                    depth + 1,
                    evidence,
                )
            }
            ExprNode::Send {
                recv,
                method,
                args,
                block: None,
                ..
            } if args.is_empty() => {
                let receiver = match recv {
                    Some(r) => self.eval(r, env, object, depth + 1, evidence)?,
                    None => object.clone(),
                };
                if matches!(receiver, Value::Nil) && method.as_str() == "presence" {
                    return Some(Value::Nil);
                }
                let Value::Object(class, _) = &receiver else {
                    return None;
                };
                let (_, method) = self.method(class, method.as_str(), 0)?;
                if !method.params.is_empty() || method.block_param.is_some() {
                    return None;
                }
                evidence.push(method.name_span);
                self.eval(
                    &method.body,
                    &BTreeMap::new(),
                    &receiver,
                    depth + 1,
                    evidence,
                )
            }
            _ => None,
        }
    }
}
fn sealed(index: &Index, owner: &str, value: &Value) -> bool {
    let Value::Object(_, fields) = value else {
        return false;
    };
    fn writes(e: &Expr, fields: &BTreeMap<String, Value>) -> bool {
        let direct = matches!(&*e.node, ExprNode::Assign { target: LValue::Ivar { name }, .. } | ExprNode::OpAssign { target: LValue::Ivar { name }, .. } if fields.contains_key(name.as_str()));
        let mut any = direct;
        e.node.for_each_child(&mut |e| any |= writes(e, fields));
        any
    }
    fn methods(index: &Index, owner: &str, fields: &BTreeMap<String, Value>, depth: usize) -> bool {
        if depth > 20 {
            return false;
        }
        let Some(c) = index.classes.get(owner) else {
            return false;
        };
        c.methods
            .iter()
            .filter(|m| m.receiver == MethodReceiver::Instance && m.name.as_str() != "initialize")
            .all(|m| !writes(&m.body, fields))
            && c.includes
                .iter()
                .all(|m| methods(index, m.0.as_str(), fields, depth + 1))
    }
    methods(index, owner, fields, 0)
        && fields.values().all(|v| match v {
            Value::Object(c, _) => sealed(index, c, v),
            _ => true,
        })
}
fn rewrite(
    expr: &mut Expr,
    owner: &str,
    method: &str,
    value: &Value,
    index: &Index,
    report: &mut Report,
) {
    if expr.nested_def().is_some() || matches!(&*expr.node, ExprNode::Lambda { .. }) {
        return;
    }
    if let ExprNode::BoolOp {
        op: BoolOpKind::And,
        left,
        ..
    } = &*expr.node
    {
        let mut evidence = Vec::new();
        if let Some(result @ (Value::Nil | Value::Bool(false))) =
            index.eval(left, &BTreeMap::new(), value, 0, &mut evidence)
        {
            report.rewrites.push(Rewrite {
                owner: owner.into(),
                method: method.into(),
                expression: expr.span,
                retained_left: left.span,
                result: format!("{result:?}"),
                witnesses: evidence,
            });
            let error = Expr::new(
                expr.span,
                ExprNode::Raise {
                    value: Expr::new(
                        expr.span,
                        ExprNode::Lit {
                            value: Literal::Str {
                                value: format!(
                                    "unsupported construction context: {owner}#{method} requires a falsy predicate"
                                ),
                            },
                        },
                    ),
                },
            );
            if let ExprNode::BoolOp { right, .. } = &mut *expr.node {
                *right = error;
            }
            return;
        }
    }
    expr.node
        .for_each_child_mut(&mut |e| rewrite(e, owner, method, value, index, report));
}
fn guard(method: &mut MethodDef, owner: &str) {
    let span = method.name_span;
    let mut exprs = Vec::new();
    for p in &method.params {
        let nil = Expr::new(
            span,
            ExprNode::Lit {
                value: Literal::Nil,
            },
        );
        let variable = Expr::new(
            span,
            ExprNode::Var {
                id: crate::ident::VarId(0),
                name: p.name.clone(),
            },
        );
        let condition = Expr::new(
            span,
            ExprNode::Send {
                recv: Some(nil.clone()),
                method: Symbol::from("equal?"),
                args: vec![variable],
                block: None,
                parenthesized: true,
            },
        );
        let error = Expr::new(
            span,
            ExprNode::Raise {
                value: Expr::new(
                    span,
                    ExprNode::Lit {
                        value: Literal::Str {
                            value: format!(
                                "unsupported construction context: {owner} requires nil for {}",
                                p.name
                            ),
                        },
                    },
                ),
            },
        );
        exprs.push(Expr::new(
            span,
            ExprNode::If {
                cond: condition,
                then_branch: nil,
                else_branch: error,
            },
        ));
    }
    exprs.push(method.body.clone());
    method.body = Expr::new(method.body.span, ExprNode::Seq { exprs });
}

/// Explicit source roots are part of the checked world, not assumed oracle data.
/// Returning refusals never changes the input. Unknown contexts keep dependencies.
pub fn specialize(app: &mut App, roots: &[RootSource]) -> Report {
    let mut report = Report { scope: "guarded nil-construction contexts only; not authenticated/admin or complete application acceptance".into(), roots: roots.iter().map(|r| r.path.clone()).collect(), ..Default::default() };
    if roots.is_empty() {
        report
            .refusals
            .push("explicit source roots are required".into());
        return report;
    }
    let mut index = Index {
        classes: BTreeMap::new(),
        duplicates: BTreeSet::new(),
    };
    for c in app.library_classes.iter().filter(|c| c.origin.is_none()) {
        let name = c.name.to_string();
        if index.classes.insert(name.clone(), c.clone()).is_some() {
            index.duplicates.insert(name);
        }
    }
    report.source_catalogue = app.sources.iter().map(|s| s.path.clone()).collect();
    let names = index.classes.keys().cloned().collect();
    let mut world = World {
        classes: &names,
        extra: false,
        bad: Vec::new(),
        constructors: BTreeMap::new(),
        includes: BTreeMap::new(),
    };
    report.assumptions = vec![
        "Explicit roots and ingested Ruby sources describe the selected closed code world, not the complete application".into(),
        "Literal requires use the ordinary trusted target runtime; applicable application/plugin overrides must be supplied and checked separately".into(),
        "Nil presence and ordinary class allocation are core protocols; source overrides are refused".into(),
        "Constructor argument guards and a falsy-predicate runtime guard refuse violated facts before the removed dependency could execute".into(),
    ];
    for source in &app.sources {
        if !source.path.ends_with(".rb") {
            continue;
        }
        report.ruby_sources.push(source.path.clone());
        let parsed = ruby_prism::parse(source.text.as_bytes());
        if parsed.errors().next().is_some() {
            world
                .bad
                .push(format!("unparsed source world: {}", source.path));
            continue;
        }
        world.visit(&parsed.node());
    }
    world.extra = true;
    for root in roots {
        let parsed = ruby_prism::parse(root.text.as_bytes());
        if parsed.errors().next().is_some() {
            world.bad.push(format!("unparsed root: {}", root.path));
            continue;
        }
        world.visit(&parsed.node());
    }
    // Nil presence/identity and default allocation are protocol assumptions,
    // checked against the actual supplied source world, not application names.
    if index.classes.iter().any(|(name, c)| {
        (matches!(
            name.as_str(),
            "Object" | "BasicObject" | "NilClass" | "Class"
        ) && (!c.includes.is_empty()
            || c.methods.iter().any(|m| {
                matches!(
                    m.name.as_str(),
                    "new" | "initialize" | "presence" | "equal?" | "method_missing"
                )
            })))
            || c.methods
                .iter()
                .any(|m| m.name.as_str() == "method_missing")
    }) {
        world
            .bad
            .push("source overrides a required immutable core protocol".into());
    }
    if !world.bad.is_empty() {
        world.bad.sort();
        world.bad.dedup();
        report.refusals = world.bad;
        return report;
    }
    let mut facts = BTreeMap::new();
    for (name, calls) in &world.constructors {
        if calls.is_empty()
            || calls.iter().any(|nil| !nil)
            || index
                .classes
                .values()
                .any(|c| c.parent.as_ref().is_some_and(|p| p.0.as_str() == name))
        {
            continue;
        }
        let mut evidence = Vec::new();
        if index.classes.get(name).is_some_and(|c| {
            !c.methods
                .iter()
                .any(|m| m.receiver == MethodReceiver::Instance && m.name.as_str() == "initialize")
                && index.method(name, "initialize", 0).is_some()
        }) {
            continue;
        }
        if let Some(value) = index
            .object(name, 0, &mut evidence)
            .filter(|value| sealed(&index, name, value))
        {
            facts.insert(name.clone(), value);
        }
    }
    let mut used = BTreeSet::new();
    for class in &mut app.library_classes {
        let name = class.name.to_string();
        if class.is_module && world.includes.get(&name) != Some(&1) {
            continue;
        }
        let owners: Vec<_> = if class.is_module {
            index
                .classes
                .iter()
                .filter(|(_, c)| c.includes.iter().any(|m| m.0.as_str() == name))
                .map(|(n, _)| n.clone())
                .collect()
        } else {
            vec![name.clone()]
        };
        if owners.len() != 1 {
            continue;
        }
        let owner = &owners[0];
        let Some(value) = facts.get(owner) else {
            continue;
        };
        let before = report.rewrites.len();
        for method in class
            .methods
            .iter_mut()
            .filter(|m| m.receiver == MethodReceiver::Instance && m.name.as_str() != "initialize")
        {
            rewrite(
                &mut method.body,
                &name,
                method.name.as_str(),
                value,
                &index,
                &mut report,
            );
        }
        if report.rewrites.len() != before {
            used.insert(owner.clone());
        }
    }
    for owner in used {
        let Value::Object(_, fields) = &facts[&owner] else {
            continue;
        };
        for class in app
            .library_classes
            .iter_mut()
            .filter(|c| c.name.0.as_str() == owner)
        {
            if let Some(init) = class
                .methods
                .iter_mut()
                .find(|m| m.receiver == MethodReceiver::Instance && m.name.as_str() == "initialize")
            {
                report.contexts.push(Context {
                    class: owner.clone(),
                    constructor: init.name_span,
                    nil_parameters: init.params.iter().map(|p| p.name.to_string()).collect(),
                    fields: fields.keys().cloned().collect(),
                });
                guard(init, &owner);
            }
        }
    }
    report
}
