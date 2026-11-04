//! Typed runtime singleton-definition events. A source template stays a closure
//! in its factory; only its method receiver becomes an explicit argument. No
//! native method is installed ahead of its original runtime event.
use crate::app::RuntimeDefinitionFamily;
use crate::dialect::{LibraryClass, MethodReceiver};
use crate::expr::{Expr, ExprNode, LValue, Literal};
use crate::span::Span;
use crate::ty::Ty;
use crate::{App, ClassId, Symbol};
use std::collections::{BTreeMap, BTreeSet};

mod admission;
use crate::analyze::class_storage_patterns as storage;

type Names = BTreeSet<Symbol>;
type Env = BTreeMap<Symbol, Names>;
#[derive(Clone)]
struct Site {
    original: Expr,
    names: Names,
    open_name: bool,
    result: Ty,
}
#[derive(Clone)]
struct Family {
    owner: ClassId,
    extensions: Vec<ClassId>,
    extension_apis: Names,
    extension_arities: BTreeMap<Symbol, usize>,
    registry: ClassId,
    descendants: Names,
    names: Names,
    open_names: bool,
    native_names: Names,
    sites: Vec<Site>,
    result: Ty,
    storage: BTreeMap<Symbol, Ty>,
    storage_patterns: Vec<crate::app::RuntimeClassStoragePattern>,
    parents: BTreeMap<Symbol, Option<ClassId>>,
    callback: bool,
}

pub(crate) fn prepare(app: &mut App, target: crate::build_target::BuildTarget) -> bool {
    use crate::build_target::BuildTarget::*;
    if !matches!(target, Ruby | Jruby | Spinel) || !app.runtime_definition_families.is_empty() {
        return false;
    }
    let mut families = Vec::new();
    for class in &app.library_classes {
        let mut index = families.len();
        while let Some(family) = discover(app, class, index) {
            if families
                .iter()
                .any(|prior: &Family| prior.registry == family.registry)
            {
                index += 1;
                continue;
            }
            families.push(family);
            break;
        }
    }
    if families.is_empty() {
        return false;
    }
    // Build helpers before mutating any original event. A failed typed runtime
    // template never licenses removing the source's unsupported declaration.
    let mut helpers = Vec::new();
    for family in &families {
        let mut generated = match runtime_classes(family) {
            Ok(generated) => generated,
            Err(error) => {
                if std::env::var_os("ROUNDHOUSE_FAMILY_DEBUG").is_some() {
                    eprintln!("runtime family helper: {error}");
                }
                return false;
            }
        };
        helpers.append(&mut generated);
    }
    for family in &families {
        // A real singleton_method_added callback can run when the source
        // class defines the callback itself. Materialize the complete typed
        // runtime before that class loads, not only at its later call sites.
        app.library_load_dependencies
            .entry(family.owner.clone())
            .or_default()
            .push(family.registry.clone());
        for module in &family.extensions {
            app.library_load_dependencies
                .entry(module.clone())
                .or_default()
                .push(family.registry.clone());
        }
        let nested_prefix = format!("{}::", family.registry.0);
        app.library_load_dependencies
            .entry(family.registry.clone())
            .or_default()
            .extend(
                helpers
                    .iter()
                    .filter(|class| class.name.0.as_str().starts_with(&nested_prefix))
                    .map(|class| class.name.clone()),
            );
        for class in &mut app.library_classes {
            let class_side = family.descendants.contains(&class.name.0);
            for method in &mut class.methods {
                let extension = family.extensions.contains(&class.name);
                let context = class_side && method.receiver == MethodReceiver::Class
                    || extension && method.receiver == MethodReceiver::Instance;
                rewrite(&mut method.body, family, context, &mut Env::new());
                for default in method
                    .params
                    .iter_mut()
                    .filter_map(|param| param.default.as_mut())
                {
                    rewrite(default, family, context, &mut Env::new());
                }
                if extension {
                    let marker = if method.receiver == MethodReceiver::Instance {
                        Some(service(
                            family,
                            "require_extension",
                            vec![Expr::new(method.body.span, ExprNode::SelfRef)],
                        ))
                    } else if method.name.as_str() == "extended"
                        && let [param] = method.params.as_slice()
                    {
                        Some(service(
                            family,
                            "activate_extension",
                            vec![var(param.name.as_str())],
                        ))
                    } else {
                        None
                    };
                    if let Some(marker) = marker {
                        let before = method.body.clone();
                        method.body = Expr::new(
                            before.span,
                            ExprNode::Seq {
                                exprs: vec![marker, before],
                            },
                        );
                    }
                }
            }
            for (_, value) in &mut class.constants {
                rewrite(value, family, class_side, &mut Env::new());
            }
            for call in &mut class.unknown_calls {
                rewrite(call, family, class_side, &mut Env::new());
            }
            for init in &mut class.class_ivar_initializers {
                rewrite(init, family, class_side, &mut Env::new());
            }
        }
        // Library roots need their class-side context and must not be visited
        // twice: a fallback query must not recursively wrap itself. Survey the
        // remaining executable inventory without removing any emitted source.
        let libraries = std::mem::take(&mut app.library_classes);
        super::for_each_emit_body(app, &mut |body| {
            rewrite(body, family, false, &mut Env::new())
        });
        app.library_classes = libraries;
        app.runtime_definition_families
            .push(RuntimeDefinitionFamily {
                owner: family.owner.clone(),
                registry: family.registry.clone(),
                names: family.names.iter().cloned().collect(),
                open_names: family.open_names,
                result: family.result.clone(),
                receiver_parents: family
                    .parents
                    .iter()
                    .map(|(name, parent)| (ClassId(name.clone()), parent.clone()))
                    .collect(),
                storage: family
                    .storage
                    .iter()
                    .map(|(name, ty)| (name.clone(), ty.clone()))
                    .collect(),
                original_installs: family
                    .sites
                    .iter()
                    .map(|site| site.original.clone())
                    .collect(),
            });
    }
    // These concrete runtime contracts are declarations, not inferred source
    // signatures: keep them authoritative through the ordinary second analysis.
    for class in &helpers {
        let signatures = app.rbs_signatures.entry(class.name.clone()).or_default();
        for method in &class.methods {
            if let Some(signature) = &method.signature {
                signatures.insert(method.name.clone(), signature.clone());
            }
        }
    }
    app.library_classes.extend(helpers);
    true
}

fn discover(app: &App, class: &LibraryClass, index: usize) -> Option<Family> {
    if class.is_module
        || class.parent.is_some()
        || !class.includes.is_empty()
        || class.origin.is_some()
        || class.name.0.as_str().contains("::")
        || app
            .library_classes
            .iter()
            .filter(|other| other.name == class.name)
            .count()
            != 1
        || app.library_classes.iter().any(|other| {
            matches!(
                other.name.0.as_str(),
                "Object" | "BasicObject" | "Class" | "Module" | "Kernel"
            )
        })
        || class.methods.iter().any(|method| {
            method.receiver == MethodReceiver::Class
                && matches!(
                    method.name.as_str(),
                    "define_singleton_method"
                        | "singleton_class"
                        | "respond_to?"
                        | "respond_to_missing?"
                        | "method_missing"
                        | "send"
                        | "__send__"
                        | "public_send"
                        | "method"
                        | "public_method"
                        | "private_class_method"
                        | "public_class_method"
                        | "const_added"
                )
        })
    {
        return None;
    }
    let extensions: Vec<_> = app
        .runtime_extension_events
        .iter()
        .filter(|event| event.owner == class.name)
        .map(|event| event.module.clone())
        .collect();
    if extensions.len() > 1 {
        return None;
    }
    let extension_classes: Vec<_> = app
        .library_classes
        .iter()
        .filter(|module| extensions.contains(&module.name))
        .collect();
    let extension_apis: Names = extension_classes
        .iter()
        .flat_map(|module| &module.methods)
        .filter(|method| method.receiver == MethodReceiver::Instance)
        .map(|method| method.name.clone())
        .collect();
    let extension_arities = extension_classes
        .iter()
        .flat_map(|module| &module.methods)
        .filter(|method| method.receiver == MethodReceiver::Instance)
        .map(|method| (method.name.clone(), method.params.len()))
        .collect();
    if class.methods.iter().any(|method| {
        method.receiver == MethodReceiver::Class && extension_apis.contains(&method.name)
    }) {
        return None;
    }
    let mut sites = Vec::new();
    // A source-derived finite name domain is evidence, not eager installation:
    // the runtime still chooses and installs its actual name at the event.
    for method in class
        .methods
        .iter()
        .filter(|method| method.receiver == MethodReceiver::Class)
    {
        discover_sites(&method.body, &mut Env::new(), &mut sites);
    }
    for module in &extension_classes {
        for method in module
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Instance)
        {
            discover_sites(&method.body, &mut Env::new(), &mut sites);
        }
    }
    if std::env::var_os("ROUNDHOUSE_FAMILY_DEBUG").is_some() {
        eprintln!(
            "runtime family {} sites {:?}",
            class.name.0,
            sites
                .iter()
                .map(|site| (&site.names, &site.result))
                .collect::<Vec<_>>()
        );
    }
    if sites.is_empty() {
        return None;
    }
    if sites
        .iter()
        .any(|site| site.result.is_unknown() || site.result.is_open())
    {
        return None;
    }
    let result = sites
        .iter()
        .map(|site| site.result.clone())
        .reduce(crate::analyze::union_of)?;
    let open_names = sites.iter().any(|site| site.open_name);
    let mut names: Names = sites
        .iter()
        .flat_map(|site| site.names.iter().cloned())
        .collect();
    let mut descendants = BTreeSet::from([class.name.0.clone()]);
    loop {
        let old = descendants.len();
        for other in &app.library_classes {
            if other
                .parent
                .as_ref()
                .is_some_and(|parent| descendants.contains(&parent.0))
            {
                descendants.insert(other.name.0.clone());
            }
        }
        if old == descendants.len() {
            break;
        }
    }
    // Alias destination names join the protocol domain, but not the set of
    // methods visible before the corresponding original alias event.
    for other in app
        .library_classes
        .iter()
        .filter(|other| descendants.contains(&other.name.0))
    {
        for method in other
            .methods
            .iter()
            .filter(|method| method.receiver == MethodReceiver::Class)
        {
            alias_names(&method.body, &mut Env::new(), &mut names);
        }
    }
    if names.iter().any(|name| {
        crate::emit::audit::CLASS_METHODS.contains(&name.as_str())
            || app
                .library_classes
                .iter()
                .filter(|other| descendants.contains(&other.name.0))
                .flat_map(|other| &other.methods)
                .any(|method| method.receiver == MethodReceiver::Class && &method.name == name)
    }) {
        return None;
    }
    // Every helper leaf is globally unique too: native class ABIs cannot
    // distinguish two nested classes with the same emitted leaf name.
    let mut unique = index;
    let registry = loop {
        let prefix = format!("RoundhouseRuntimeFamily{unique}");
        if !app.library_classes.iter().any(|other| {
            other
                .name
                .0
                .as_str()
                .split("::")
                .any(|part| part.starts_with(&prefix))
                || other
                    .constants
                    .iter()
                    .any(|(name, _)| name.as_str().starts_with(&prefix))
        }) && !app
            .models
            .iter()
            .any(|other| other.name.0.as_str().starts_with(&prefix))
        {
            break ClassId(Symbol::from(prefix));
        }
        unique += 1;
    };
    let mut storage = BTreeMap::new();
    for site in &sites {
        walk(&site.original, &mut |expr| {
            let field = match &*expr.node {
                ExprNode::Ivar { name } => expr.ty.as_ref().map(|ty| (name, ty)),
                ExprNode::Assign {
                    target: LValue::Ivar { name },
                    value,
                } => value.ty.as_ref().map(|ty| (name, ty)),
                _ => None,
            };
            if let Some((name, ty)) = field {
                let previous = storage.remove(name).unwrap_or(Ty::Nil);
                storage.insert(name.clone(), crate::analyze::union_of(previous, ty.clone()));
            }
        });
    }
    if std::env::var_os("ROUNDHOUSE_FAMILY_DEBUG").is_some() {
        eprintln!("family storage {storage:?}");
    }
    if storage.values().any(Ty::mentions_unknown) {
        return None;
    }
    let parents = app
        .library_classes
        .iter()
        .filter(|class| descendants.contains(&class.name.0))
        .map(|class| (class.name.0.clone(), class.parent.clone()))
        .collect();
    let mut native_names: Names = crate::emit::audit::CLASS_METHODS
        .iter()
        .copied()
        .map(Symbol::from)
        .collect();
    native_names.extend(extension_apis.iter().cloned());
    native_names.extend(
        app.library_classes
            .iter()
            .filter(|class| descendants.contains(&class.name.0))
            .flat_map(|class| &class.methods)
            .filter(|method| method.receiver == MethodReceiver::Class)
            .map(|method| method.name.clone()),
    );
    let family = Family {
        storage_patterns: app
            .runtime_class_storage_patterns
            .iter()
            .filter(|pattern| pattern.owner == class.name)
            .cloned()
            .collect(),
        open_names,
        native_names,
        owner: class.name.clone(),
        extensions,
        extension_apis,
        extension_arities,
        registry,
        descendants,
        names,
        sites,
        result,
        storage,
        parents,
        callback: class.methods.iter().any(|method| {
            method.receiver == MethodReceiver::Class
                && method.name.as_str() == "singleton_method_added"
        }),
    };
    admission::shape(app, &family).then_some(family)
}

fn domain(expr: &Expr, env: &Env) -> Names {
    match &*expr.node {
        ExprNode::Lit {
            value: Literal::Sym { value },
        } => BTreeSet::from([value.clone()]),
        ExprNode::Lit {
            value: Literal::Str { value },
        } => BTreeSet::from([Symbol::from(value.as_str())]),
        ExprNode::Var { name, .. } => env.get(name).cloned().unwrap_or_default(),
        ExprNode::If {
            then_branch,
            else_branch,
            ..
        } => {
            let left = domain(then_branch, env);
            let right = domain(else_branch, env);
            if left.is_empty() || right.is_empty() {
                Names::new()
            } else {
                left.union(&right).cloned().collect()
            }
        }
        ExprNode::Seq { exprs } => exprs
            .last()
            .map(|last| domain(last, env))
            .unwrap_or_default(),
        ExprNode::Send {
            recv: Some(recv),
            method,
            args,
            block: None,
            ..
        } if args.is_empty() && matches!(method.as_str(), "to_sym" | "to_s") => domain(recv, env),
        _ => Names::new(),
    }
}
fn family_name(expr: &Expr, env: &Env, family: &Family) -> bool {
    let names = domain(expr, env);
    if family.open_names {
        expr.ty.as_ref().is_some_and(Ty::is_stringish) && names.is_disjoint(&family.native_names)
    } else {
        !names.is_empty() && names.is_subset(&family.names)
    }
}
fn discover_sites(expr: &Expr, env: &mut Env, sites: &mut Vec<Site>) {
    if let ExprNode::Seq { exprs } = &*expr.node {
        for child in exprs {
            discover_sites(child, env, sites);
        }
        return;
    }
    if let ExprNode::Assign {
        target: LValue::Var { name, .. },
        value,
    } = &*expr.node
    {
        env.insert(name.clone(), domain(value, env));
    }
    if let ExprNode::Send {
        recv,
        method,
        args,
        block: Some(block),
        ..
    } = &*expr.node
        && recv
            .as_ref()
            .is_none_or(|recv| matches!(&*recv.node, ExprNode::SelfRef))
        && method.as_str() == "define_singleton_method"
        && let [name] = args.as_slice()
        && let ExprNode::Lambda {
            params,
            rest_param: None,
            extra_params,
            block_param: None,
            body,
            ..
        } = &*block.node
        && params.is_empty()
        && extra_params.is_empty()
    {
        let names = domain(name, env);
        let open_name = names.is_empty() && name.ty.as_ref().is_some_and(Ty::is_stringish);
        if (!names.is_empty() || open_name)
            && admission::template(body)
            && let Some(result) = &body.ty
            && data_result(result)
        {
            sites.push(Site {
                original: expr.clone(),
                names,
                open_name,
                result: result.clone(),
            });
        }
        return;
    }
    expr.node
        .for_each_child(&mut |child| discover_sites(child, &mut env.clone(), sites));
    forget_nested_writes(expr, env);
}
fn alias_names(expr: &Expr, env: &mut Env, names: &mut Names) {
    if let ExprNode::Seq { exprs } = &*expr.node {
        for child in exprs {
            alias_names(child, env, names);
        }
        return;
    }
    if let ExprNode::Assign {
        target: LValue::Var { name, .. },
        value,
    } = &*expr.node
    {
        env.insert(name.clone(), domain(value, env));
    }
    if let ExprNode::Send { method, args, .. } = &*expr.node
        && method.as_str() == "alias_method"
        && args.len() == 2
    {
        names.extend(domain(&args[0], env));
    }
    expr.node
        .for_each_child(&mut |child| alias_names(child, &mut env.clone(), names));
    forget_nested_writes(expr, env);
}
fn data_result(ty: &Ty) -> bool {
    match ty {
        Ty::Int | Ty::Float | Ty::Bool | Ty::Str | Ty::Sym | Ty::Nil => true,
        Ty::Array { elem } => data_result(elem),
        Ty::Hash { key, value } => data_result(key) && data_result(value),
        Ty::Union { variants } => variants.iter().all(data_result),
        _ => false,
    }
}
// A conditional/block write is not a fact on the following path. Retaining
// the old literal domain would claim the wrong runtime name was installed.
fn forget_nested_writes(expr: &Expr, env: &mut Env) {
    expr.node.for_each_child(&mut |child| {
        walk(child, &mut |node| {
            if let ExprNode::Assign {
                target: LValue::Var { name, .. },
                ..
            }
            | ExprNode::OpAssign {
                target: LValue::Var { name, .. },
                ..
            } = &*node.node
            {
                env.remove(name);
            }
            if let ExprNode::MultiAssign { targets, .. } = &*node.node {
                for target in targets {
                    if let LValue::Var { name, .. } = target {
                        env.remove(name);
                    }
                }
            }
        })
    });
}
fn walk(expr: &Expr, f: &mut impl FnMut(&Expr)) {
    f(expr);
    expr.node.for_each_child(&mut |child| walk(child, f));
}
fn generated_const(name: &str) -> Expr {
    let mut expr = Expr::new(
        Span::synthetic(),
        ExprNode::Const {
            path: name.split("::").map(Symbol::from).collect(),
        },
    );
    expr.decisions |= crate::expr::GENERATED_CONST_REF | crate::expr::RESOLVED_CLASS_REF;
    expr
}
fn var(name: &str) -> Expr {
    Expr::new(
        Span::synthetic(),
        ExprNode::Var {
            id: crate::ident::VarId(0),
            name: Symbol::from(name),
        },
    )
}
fn sym(name: &str) -> Expr {
    Expr::new(
        Span::synthetic(),
        ExprNode::Lit {
            value: Literal::Sym {
                value: Symbol::from(name),
            },
        },
    )
}
fn boolean(value: bool) -> Expr {
    Expr::new(
        Span::synthetic(),
        ExprNode::Lit {
            value: Literal::Bool { value },
        },
    )
}
fn send(recv: Expr, name: &str, args: Vec<Expr>) -> Expr {
    Expr::new(
        Span::synthetic(),
        ExprNode::Send {
            recv: Some(recv),
            method: Symbol::from(name),
            args,
            block: None,
            parenthesized: true,
        },
    )
}
fn service(family: &Family, name: &str, args: Vec<Expr>) -> Expr {
    send(generated_const(family.registry.0.as_str()), name, args)
}
fn owner_receiver(recv: Option<&Expr>, family: &Family, self_class: bool) -> Option<Expr> {
    match recv.map(|recv| &*recv.node) {
        None | Some(ExprNode::SelfRef) if self_class => {
            Some(Expr::new(Span::synthetic(), ExprNode::SelfRef))
        }
        Some(ExprNode::Const { path })
            if family.descendants.contains(&Symbol::from(
                path.iter()
                    .map(Symbol::as_str)
                    .filter(|part| !part.is_empty())
                    .collect::<Vec<_>>()
                    .join("::"),
            )) =>
        {
            recv.cloned()
        }
        Some(ExprNode::Var { .. }) if recv.is_some_and(|recv| {
            matches!(&recv.ty, Some(Ty::Class { id, args }) if id.0.as_str() == "Class" && matches!(args.as_slice(), [Ty::Class { id, .. }] if family.descendants.contains(&id.0)))
                && recv.decisions & crate::expr::CLASS_OBJECT_VALUE != 0
        }) => recv.cloned(),
        _ => None,
    }
}
fn callback(family: &Family) -> Expr {
    let receiver = var("__rh_event_receiver");
    let name = var("__rh_event_name");
    let body = if family.callback {
        Expr::new(
            Span::synthetic(),
            ExprNode::Seq {
                exprs: vec![
                    send(receiver, "send", vec![sym("singleton_method_added"), name]),
                    Expr::new(
                        Span::synthetic(),
                        ExprNode::Lit {
                            value: Literal::Nil,
                        },
                    ),
                ],
            },
        )
    } else {
        Expr::new(
            Span::synthetic(),
            ExprNode::Lit {
                value: Literal::Nil,
            },
        )
    };
    lambda(vec!["__rh_event_receiver", "__rh_event_name"], body)
}
fn lambda(params: Vec<&str>, body: Expr) -> Expr {
    Expr::new(
        Span::synthetic(),
        ExprNode::Lambda {
            params: params.into_iter().map(Symbol::from).collect(),
            rest_param: None,
            extra_params: Vec::new(),
            block_param: None,
            body,
            block_style: Default::default(),
        },
    )
}
fn lift(expr: &mut Expr) {
    expr.node.for_each_child_mut(&mut lift);
    let replacement = match &*expr.node {
        ExprNode::SelfRef => Some(var("__rh_method_receiver")),
        ExprNode::Ivar { name } => Some(send(var("__rh_method_receiver"), "instance_variable_get", vec![sym(&format!("@{name}"))])),
        ExprNode::Assign { target: LValue::Ivar { name }, value } => Some(send(var("__rh_method_receiver"), "instance_variable_set", vec![sym(&format!("@{name}")), value.clone()])),
        ExprNode::Send { recv, method, args, block: None, .. } if method.as_str() == "__method__" && args.is_empty()
            && recv.as_ref().is_none_or(|recv| matches!(&*recv.node, ExprNode::Var { name, .. } if name.as_str() == "__rh_method_receiver")) => Some(var("__rh_original_name")),
        ExprNode::Send { recv, method, args, block: None, .. } if method.as_str() == "__callee__" && args.is_empty()
            && recv.as_ref().is_none_or(|recv| matches!(&*recv.node, ExprNode::Var { name, .. } if name.as_str() == "__rh_method_receiver")) => Some(var("__rh_called_name")),
        ExprNode::Send { recv: None, method, args, block: None, .. }
            if matches!(method.as_str(), "instance_variable_get" | "instance_variable_set") => Some(send(var("__rh_method_receiver"), method.as_str(), args.clone())),
        ExprNode::Send { recv: None, method, args, block, .. } => {
            let mut call = send(var("__rh_method_receiver"), "send", std::iter::once(sym(method.as_str())).chain(args.iter().cloned()).collect());
            if let ExprNode::Send { block: output, .. } = &mut *call.node { *output = block.clone(); }
            Some(call)
        }
        _ => None,
    };
    if let Some(mut replacement) = replacement {
        replacement.span = expr.span;
        replacement.ty = expr.ty.clone();
        *expr = replacement;
    }
}

fn rewrite(expr: &mut Expr, family: &Family, self_class: bool, env: &mut Env) {
    if let ExprNode::Seq { exprs } = &mut *expr.node {
        for child in exprs {
            rewrite(child, family, self_class, env);
        }
        return;
    }
    if let ExprNode::Assign {
        target: LValue::Var { name, .. },
        value,
    } = &*expr.node
    {
        env.insert(name.clone(), domain(value, env));
    }
    if let Some(site) = family
        .sites
        .iter()
        .find(|site| site.original.span == expr.span && site.original.node == expr.node)
    {
        let ExprNode::Send {
            args,
            block: Some(block),
            ..
        } = &*expr.node
        else {
            return;
        };
        let ExprNode::Lambda { body, .. } = &*block.node else {
            return;
        };
        let mut lifted = body.clone();
        lift(&mut lifted);
        let mut event = service(
            family,
            "install",
            vec![
                Expr::new(expr.span, ExprNode::SelfRef),
                send(args[0].clone(), "to_sym", vec![]),
                lambda(
                    vec![
                        "__rh_method_receiver",
                        "__rh_called_name",
                        "__rh_original_name",
                    ],
                    lifted,
                ),
                callback(family),
            ],
        );
        event.span = expr.span;
        event.ty = Some(Ty::Sym);
        *expr = event;
        let _ = site;
        return;
    }
    // Operations on a source singleton class are events on its source owner,
    // not a native runtime Class object fabricated by the emitter.
    if let ExprNode::Send {
        recv: Some(recv),
        method,
        args,
        block: None,
        ..
    } = &*expr.node
        && method.as_str() == "alias_method"
        && args.len() == 2
        && let ExprNode::Send {
            recv: owner,
            method: singleton,
            args: noargs,
            block: None,
            ..
        } = &*recv.node
        && singleton.as_str() == "singleton_class"
        && noargs.is_empty()
        && let Some(owner) = owner_receiver(owner.as_ref(), family, self_class)
        && family_name(&args[0], env, family)
        && family_name(&args[1], env, family)
    {
        let mut call = service(
            family,
            "alias_name",
            vec![
                owner,
                send(args[0].clone(), "to_sym", vec![]),
                send(args[1].clone(), "to_sym", vec![]),
                callback(family),
            ],
        );
        call.span = expr.span;
        *expr = call;
        return;
    }
    if let ExprNode::Send {
        recv,
        method,
        args,
        block: None,
        ..
    } = &*expr.node
        && let Some(owner) = owner_receiver(recv.as_ref(), family, self_class)
    {
        let subset = args
            .first()
            .is_some_and(|argument| family_name(argument, env, family));
        let replacement = match method.as_str() {
            "respond_to?" if args.len() == 1 || args.len() == 2 => {
                let private = args.get(1).cloned().unwrap_or_else(|| boolean(false));
                // The typed service owns the native-table fallback so every
                // source receiver/name/include-private operand runs once, even
                // when the family has no slot for that name yet.
                Some(service(
                    family,
                    "responds",
                    vec![owner, send(args[0].clone(), "to_sym", vec![]), private],
                ))
            }
            "method" | "public_method" if args.len() == 1 && subset => Some(service(
                family,
                "bind",
                vec![
                    owner,
                    send(args[0].clone(), "to_sym", vec![]),
                    boolean(method.as_str() == "public_method"),
                ],
            )),
            "private_class_method" | "public_class_method" if args.len() == 1 && subset => {
                Some(service(
                    family,
                    "set_visibility",
                    vec![
                        owner,
                        send(args[0].clone(), "to_sym", vec![]),
                        Expr::new(
                            Span::synthetic(),
                            ExprNode::Lit {
                                value: Literal::Int {
                                    value: if method.as_str() == "private_class_method" {
                                        1
                                    } else {
                                        0
                                    },
                                },
                            },
                        ),
                    ],
                ))
            }
            "public_send" | "send" | "__send__" if args.len() == 1 && subset => Some(service(
                family,
                "call",
                vec![
                    owner,
                    send(args[0].clone(), "to_sym", vec![]),
                    boolean(method.as_str() != "public_send"),
                ],
            )),
            _ if args.is_empty()
                && (family.names.contains(method)
                    || family.open_names && !family.native_names.contains(method)) =>
            {
                Some(service(
                    family,
                    "call",
                    vec![
                        owner,
                        sym(method.as_str()),
                        boolean(
                            recv.is_none()
                                || matches!(
                                    recv.as_ref().map(|recv| &*recv.node),
                                    Some(ExprNode::SelfRef)
                                ),
                        ),
                    ],
                ))
            }
            _ => None,
        };
        if let Some(mut replacement) = replacement {
            replacement.span = expr.span;
            *expr = replacement;
            return;
        }
    }
    // Class-object reflection is explicit in the capability ABI, including
    // the original pre-install cache reset. This preserves actual dynamic
    // self on inherited factory calls rather than naming the root constant.
    if self_class
        && let ExprNode::Send {
            recv, method, args, ..
        } = &mut *expr.node
        && recv.is_none()
        && matches!(
            method.as_str(),
            "instance_variable_get" | "instance_variable_set"
        )
        && args.first().and_then(storage::address).is_some()
    {
        *recv = Some(Expr::new(expr.span, ExprNode::SelfRef));
    }
    expr.node
        .for_each_child_mut(&mut |child| rewrite(child, family, self_class, &mut env.clone()));
    forget_nested_writes(expr, env);
}

fn runtime_classes(family: &Family) -> Result<Vec<LibraryClass>, String> {
    // This family admits only indexed receivers, unchanged source parents and
    // no superclass override/dynamic subclass escape. A concrete capability
    // therefore follows the real source hierarchy without an unbounded Class
    // reflection operation (which makes unrelated native constructors live).
    let mut parent_dispatch = format!("if receiver == ::{}\n  nil\n", family.owner.0);
    for (receiver, parent) in &family.parents {
        if receiver == &family.owner.0 {
            continue;
        }
        if let Some(parent) = parent {
            parent_dispatch.push_str(&format!(
                "elsif receiver == ::{receiver}\n  ::{}\n",
                parent.0
            ));
        }
    }
    parent_dispatch.push_str("else\n  raise NotImplementedError.new(\"receiver outside the proven runtime definition family\")\nend");
    let replacements = [
        ("__REGISTRY__", family.registry.0.as_str().to_string()),
        ("__OWNER__", format!("::{}", family.owner.0)),
        ("__ENTRY__", format!("{}Entry", family.registry.0)),
        ("__SLOT__", format!("{}Slot", family.registry.0)),
        ("__BOUND__", format!("{}BoundMethod", family.registry.0)),
        ("__STATE__", format!("{}State", family.registry.0)),
        (
            "__STATE_VALUE__",
            format!("{}StateValue", family.registry.0),
        ),
        ("__PARENT_DISPATCH__", parent_dispatch),
        (
            "__EXTENSION_API_DISPATCH__",
            if family.extension_apis.is_empty() {
                "false".to_string()
            } else {
                family
                    .extension_apis
                    .iter()
                    .map(|name| format!("name == :{}", name))
                    .collect::<Vec<_>>()
                    .join(" || ")
            },
        ),
        ("__RESULT__", crate::emit::ruby::ty_to_rbs(&family.result)),
    ];
    let render = |source: &str| {
        replacements
            .iter()
            .fold(source.to_string(), |source, (key, value)| {
                source.replace(key, value)
            })
    };
    let source = render(include_str!("runtime_definition_family/runtime.rb"));
    let signatures = render(include_str!("runtime_definition_family/runtime.rbs"));
    let mut classes = crate::runtime_src::parse_library_with_rbs(
        source.as_bytes(),
        &signatures,
        "<runtime-definition-family>",
    )?;
    // Generated references must carry exact class identity, not bypass lexical
    // resolution while retaining a bare nested Entry/Slot/BoundMethod name.
    let nested: BTreeMap<_, _> = classes
        .iter()
        .filter_map(|class| {
            class
                .name
                .0
                .as_str()
                .rsplit_once("::")
                .map(|(_, leaf)| (Symbol::from(leaf), class.name.clone()))
        })
        .collect();
    for class in &mut classes {
        let prepare = |expr: &mut Expr| {
            walk_mut(expr, &mut |expr| {
                if let ExprNode::Const { path } = &*expr.node
                    && let [leaf] = path.as_slice()
                    && let Some(owner) = nested.get(leaf)
                {
                    *expr = generated_const(owner.0.as_str());
                }
            });
            mark_generated(expr);
        };
        for method in &mut class.methods {
            method.name_span = Span::synthetic();
            prepare(&mut method.body);
        }
        for expr in &mut class.unknown_calls {
            prepare(expr);
        }
        for expr in &mut class.class_ivar_initializers {
            prepare(expr);
        }
        for (_, expr) in &mut class.constants {
            prepare(expr);
        }
    }
    Ok(classes)
}
fn walk_mut(expr: &mut Expr, f: &mut impl FnMut(&mut Expr)) {
    f(expr);
    expr.node
        .for_each_child_mut(&mut |child| walk_mut(child, f));
}
fn mark_generated(expr: &mut Expr) {
    expr.span = Span::synthetic();
    if matches!(&*expr.node, ExprNode::Const { .. }) {
        expr.decisions |= crate::expr::GENERATED_CONST_REF;
    }
    expr.node.for_each_child_mut(&mut mark_generated);
}

/// Facts about a remaining source event, not a second admission policy. This
/// keeps the rejection honest now that a computed name alone is supported:
/// callers still retain the original unsupported diagnostic and source span.
pub(crate) fn unadmitted_event_details(expr: &Expr) -> String {
    let ExprNode::Send { method, block, .. } = &*expr.node else {
        return String::new();
    };
    let mut facts = Vec::new();
    if method.as_str() == "define_method" {
        facts.push(
            "instance-definition receiver ownership is outside the singleton family".to_string(),
        );
    }
    if let Some(block) = block {
        if let ExprNode::Lambda {
            params,
            extra_params,
            rest_param,
            block_param,
            body,
            ..
        } = &*block.node
        {
            if !params.is_empty()
                || !extra_params.is_empty()
                || rest_param.is_some()
                || block_param.is_some()
            {
                facts.push("argument/optional-argument callable ABI remains unproved".to_string());
            }
            let mut unknown = 0;
            let mut returns = false;
            walk(body, &mut |node| {
                unknown += usize::from(node.ty.as_ref().is_none_or(Ty::mentions_unknown));
                returns |= matches!(&*node.node, ExprNode::Return { .. });
            });
            if unknown > 0 {
                facts.push(format!(
                    "{unknown} callable-body nodes have unresolved types"
                ));
            }
            if returns {
                facts.push("method-return frame semantics remain unproved".to_string());
            }
        }
    }
    if facts.is_empty() {
        facts.push(
            "receiver, storage or observer protocol is outside the admitted family".to_string(),
        );
    }
    format!(
        "; no closed typed runtime family admitted: {}",
        facts.join("; ")
    )
}
