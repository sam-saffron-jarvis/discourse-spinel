//! Derive a block argument contract from the positional arguments supplied
//! by a source method's `yield` sites.
//!
//! A `yield` inside an ordinary Ruby block is lexically attached to the
//! enclosing method, so traversal descends through `Lambda` nodes. A nested
//! `def`, however, establishes a new method frame and is excluded.

use crate::dialect::MethodDef;
use crate::effect::EffectSet;
use crate::expr::{Expr, ExprNode};
use crate::ident::Symbol;
use crate::ty::Ty;
use crate::ty::{Param, ParamKind};
use std::sync::Arc;

/// Collect the argument types for the implicit block invoked by `method`.
///
/// Each argument position joins the types from every actual yield tuple; a
/// position omitted by a shorter tuple contributes `Nil` (Ruby fills missing
/// block parameters with nil). Unknown expression annotations remain
/// `Untyped`, and an entirely absent expression annotation also becomes
/// `Untyped`. The returned function's result is deliberately `Untyped`: this
/// records only what the method passes to its block, not what the block
/// returns.
///
/// Returns `None` if the method does not yield, or if any yield has a
/// positional splat/forwarding argument whose tuple shape cannot be derived
/// statically. In particular, it never builds a contract from only the known
/// subset of yields.
pub(super) fn for_method(method: &MethodDef) -> Option<Ty> {
    let mut yields = Vec::new();
    collect_yields(&method.body, &mut yields);
    if yields.is_empty() {
        return None;
    }

    let mut tuples = Vec::with_capacity(yields.len());
    let mut max_arity = 0;
    for args in yields {
        if args.iter().any(is_ambiguous_yield_arg) {
            return None;
        }
        max_arity = max_arity.max(args.len());
        tuples.push(args);
    }

    let mut positional = Vec::with_capacity(max_arity);
    for index in 0..max_arity {
        let mut slot: Option<Ty> = None;
        let mut empty = Vec::new();
        for args in &tuples {
            let argument = args.get(index);
            let ty = argument
                .map(|arg| arg.ty.clone().unwrap_or(Ty::Untyped))
                .unwrap_or(Ty::Nil);
            if argument.is_some_and(|arg| {
                matches!(&*arg.node,
                ExprNode::Hash { entries, .. } if entries.is_empty())
                    || matches!(&*arg.node, ExprNode::Array { elements, .. } if elements.is_empty())
            }) {
                empty.push(ty);
                continue;
            }
            slot = Some(match slot {
                Some(previous) => join_observed(previous, ty),
                None => ty,
            });
        }
        // Empty literal containers contain no key/element witnesses. They
        // can adopt an observed container contract, unlike an unknown writer.
        for ty in empty {
            slot = Some(match slot {
                Some(previous) => crate::analyze::body::union_of(previous, ty),
                None => ty,
            });
        }
        positional.push(Param {
            name: Symbol::from(format!("arg{index}")),
            ty: Arc::new(slot.expect("at least one yield tuple")),
            kind: ParamKind::Required,
        });
    }

    Some(Ty::Fn {
        params: positional.into(),
        block: None,
        ret: Arc::new(Ty::Untyped),
        effects: EffectSet::singleton(crate::effect::Effect::Var {
            var: crate::ident::EffectVar(0),
        }),
    })
}

fn join_observed(previous: Ty, ty: Ty) -> Ty {
    if previous == ty {
        return ty;
    }
    match (previous, ty) {
        (Ty::Hash { key: ak, value: av }, Ty::Hash { key: bk, value: bv }) => Ty::Hash {
            key: Arc::new(join_observed((*ak).clone(), (*bk).clone())),
            value: Arc::new(join_observed((*av).clone(), (*bv).clone())),
        },
        (Ty::Array { elem: a }, Ty::Array { elem: b }) => Ty::Array {
            elem: Arc::new(join_observed((*a).clone(), (*b).clone())),
        },
        (a, b) if a.mentions_unknown() || b.mentions_unknown() => Ty::Untyped,
        (a, b) => crate::analyze::body::union_of(a, b),
    }
}

fn is_ambiguous_yield_arg(arg: &Expr) -> bool {
    matches!(
        &*arg.node,
        ExprNode::Splat { .. }
            | ExprNode::KeywordSplat { .. }
            | ExprNode::ForwardArgs
            | ExprNode::ForwardKeywords
            | ExprNode::ForwardKeywordsWithPairs { .. }
    )
}

fn collect_yields<'a>(expr: &'a Expr, out: &mut Vec<&'a [Expr]>) {
    // Ingest retains a nested `def` on its placeholder expression. Its body
    // belongs to the nested method, not the method whose body we are scanning.
    if expr.nested_def().is_some() {
        return;
    }
    if let ExprNode::Yield { args } = &*expr.node {
        out.push(args);
    }
    // Lambda represents an ordinary block as well as a lambda literal. Ruby's
    // `yield` is lexically bound to the surrounding method even in an ordinary
    // block; yielding inside a nested `def` is excluded above.
    expr.node
        .for_each_child(&mut |child| collect_yields(child, out));
}

/// Attach source-inferred block contracts inside the ordinary return fixpoint.
/// These registry wrappers are derived, not declarations: their method params
/// remain pending so `declared_param_ty` cannot freeze an old inference round.
pub(super) fn harvest(analyzer: &mut super::Analyzer, app: &crate::App) {
    use crate::dialect::MethodReceiver;
    use std::collections::BTreeMap;
    let methods: Vec<_> = app
        .library_classes
        .iter()
        .flat_map(|class| {
            class
                .methods
                .iter()
                .map(move |method| (&class.name, method))
        })
        .chain(
            app.models
                .iter()
                .flat_map(|model| model.methods().map(move |method| (&model.name, method))),
        )
        .collect();
    let mut definitions = BTreeMap::new();
    for (owner, method) in &methods {
        *definitions
            .entry(((*owner).clone(), method.name.clone(), method.receiver))
            .or_insert(0usize) += 1;
    }
    let mut contracts = BTreeMap::new();
    for (owner, method) in &methods {
        let key = ((*owner).clone(), method.name.clone(), method.receiver);
        if definitions[&key] != 1
            || method.signature.is_some()
            || app
                .rbs_signatures
                .get(*owner)
                .is_some_and(|methods| methods.contains_key(&method.name))
        {
            continue;
        }
        if let Some(contract) = for_method(method) {
            contracts.insert(key, contract);
        }
    }
    let defined = super::Analyzer::defined_methods(app);
    let mut returns: BTreeMap<super::ParamKey, Ty> = BTreeMap::new();
    // Only actual literal/typed block calls supply a return observation. The
    // yield argument contract itself never depends on a chosen consumer.
    fn visit(
        expr: &Expr,
        owner: &crate::ClassId,
        class_side: bool,
        analyzer: &super::Analyzer,
        defined: &std::collections::BTreeSet<super::ParamKey>,
        contracts: &BTreeMap<super::ParamKey, Ty>,
        returns: &mut BTreeMap<super::ParamKey, Ty>,
    ) {
        if expr.nested_def().is_some() {
            return;
        }
        if let ExprNode::Send {
            recv,
            method,
            args,
            block,
            ..
        } = &*expr.node
            && (matches!(
                method.as_str(),
                "method" | "public_method" | "instance_method" | "public_instance_method"
            ) || block.is_some()
                && matches!(method.as_str(), "send" | "__send__" | "public_send"))
        {
            // A method handle or reflective block call is not an ordinary
            // direct consumer. Do not infer its block result from some other
            // known consumer while silently ignoring this possible caller.
            let classes = recv
                .as_ref()
                .and_then(|recv| recv.ty.as_ref())
                .map(super::class_ids_for_call_receiver)
                .unwrap_or_else(|| vec![owner.clone()]);
            let literal = args.first().and_then(|arg| match &*arg.node {
                ExprNode::Lit {
                    value: crate::expr::Literal::Sym { value },
                } => Some(value.as_str()),
                ExprNode::Lit {
                    value: crate::expr::Literal::Str { value },
                } => Some(value.as_str()),
                _ => None,
            });
            for key in contracts.keys() {
                let reachable = classes.is_empty()
                    || classes.iter().any(|class| {
                        analyzer.inherited_param_owner(defined, class.clone(), &key.1, Some(key.2))
                            == key.0
                    });
                if reachable && literal.is_none_or(|name| key.1.as_str() == name) {
                    returns.insert(key.clone(), Ty::Untyped);
                }
            }
        }
        if let ExprNode::MethodRef { .. } = &*expr.node {
            // Bound callable identity can cross the source call graph. Keep
            // return debt instead of guessing which later block is supplied.
            for key in contracts.keys() {
                returns.insert(key.clone(), Ty::Untyped);
            }
        }
        if let ExprNode::Send {
            recv,
            method,
            block: Some(block),
            ..
        } = &*expr.node
        {
            let classes = recv
                .as_ref()
                .and_then(|recv| recv.ty.as_ref())
                .map(super::class_ids_for_call_receiver)
                .unwrap_or_else(|| vec![owner.clone()]);
            let side = if recv.as_ref().map_or(class_side, |recv| {
                recv.decisions & crate::expr::CLASS_OBJECT_VALUE != 0
                    || super::singleton_of(recv.ty.as_ref()).is_some()
            }) {
                MethodReceiver::Class
            } else {
                MethodReceiver::Instance
            };
            for class in classes {
                let target = analyzer.inherited_param_owner(defined, class, method, Some(side));
                let key = (target, method.clone(), side);
                if !contracts.contains_key(&key) {
                    continue;
                }
                let ret = match block.ty.as_ref() {
                    Some(Ty::Fn { ret, .. }) => (**ret).clone(),
                    _ => Ty::Untyped,
                };
                let ret = match returns.remove(&key) {
                    Some(previous) if previous.mentions_unknown() || ret.mentions_unknown() => {
                        Ty::Untyped
                    }
                    Some(previous) => super::body::union_of(previous, ret),
                    None => ret,
                };
                returns.insert(key, ret);
            }
        }
        if let ExprNode::Send {
            recv,
            method,
            args,
            block: Some(_),
            ..
        } = &*expr.node
            && matches!(
                method.as_str(),
                "instance_eval"
                    | "instance_exec"
                    | "class_eval"
                    | "class_exec"
                    | "module_eval"
                    | "module_exec"
            )
        {
            for key in contracts.keys() {
                returns.insert(key.clone(), Ty::Untyped);
            }
            if let Some(receiver) = recv {
                visit(
                    receiver, owner, class_side, analyzer, defined, contracts, returns,
                );
            }
            for argument in args {
                visit(
                    argument, owner, class_side, analyzer, defined, contracts, returns,
                );
            }
            return;
        }
        expr.node.for_each_child(&mut |child| {
            visit(
                child, owner, class_side, analyzer, defined, contracts, returns,
            )
        });
    }
    for (owner, method) in &methods {
        visit(
            &method.body,
            owner,
            method.receiver == MethodReceiver::Class,
            analyzer,
            &defined,
            &contracts,
            &mut returns,
        );
    }
    for (owner, method) in methods {
        let key = (owner.clone(), method.name.clone(), method.receiver);
        let Some(mut contract) = contracts.remove(&key) else {
            continue;
        };
        if let Ty::Fn { ret, .. } = &mut contract {
            *ret = Arc::new(returns.remove(&key).unwrap_or(Ty::Untyped));
        }
        let ret = analyzer
            .method_return_ty(owner, method)
            .unwrap_or(Ty::Untyped);
        let params = method
            .params
            .iter()
            .map(|param| Param {
                name: param.name.clone(),
                kind: param.ty_kind(),
                ty: Arc::new(Ty::Var {
                    var: crate::ident::TyVar(0),
                }),
            })
            .collect();
        let signature = Ty::Fn {
            params,
            block: Some(Arc::new(contract)),
            ret: Arc::new(ret),
            effects: method.effects.clone().union(EffectSet::singleton(
                crate::effect::Effect::Var {
                    var: crate::ident::EffectVar(0),
                },
            )),
        };
        let class = analyzer.classes.entry(owner.clone()).or_default();
        let table = if method.receiver == MethodReceiver::Class {
            &mut class.class_methods
        } else {
            &mut class.instance_methods
        };
        table.insert(method.name.clone(), signature);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dialect::{AccessorKind, MethodReceiver, MethodVisibility};
    use crate::expr::ExprNode;
    use crate::span::Span;

    fn expr(node: ExprNode, ty: Option<Ty>) -> Expr {
        let mut expr = Expr::new(Span::synthetic(), node);
        expr.ty = ty;
        expr
    }

    fn yield_expr(types: Vec<Option<Ty>>) -> Expr {
        expr(
            ExprNode::Yield {
                args: types
                    .into_iter()
                    .map(|ty| expr(ExprNode::SelfRef, ty))
                    .collect(),
            },
            None,
        )
    }

    fn method(body: Expr) -> MethodDef {
        MethodDef {
            name: Symbol::from("sample"),
            receiver: MethodReceiver::Instance,
            visibility: MethodVisibility::Public,
            params: vec![],
            unsupported_formals: None,
            has_anonymous_block: false,
            block_param: None,
            name_span: Span::synthetic(),
            body,
            signature: None,
            effects: EffectSet::pure(),
            enclosing_class: None,
            kind: AccessorKind::Method,
            is_async: false,
            mutates_self: false,
        }
    }

    fn fn_params(ty: Ty) -> Vec<Param> {
        let Ty::Fn {
            params,
            block: None,
            ret,
            ..
        } = ty
        else {
            panic!("expected block function type");
        };
        assert_eq!(*ret, Ty::Untyped);
        params.to_vec()
    }

    #[test]
    fn collects_four_positional_arguments() {
        let contract = for_method(&method(yield_expr(vec![
            Some(Ty::Int),
            Some(Ty::Str),
            Some(Ty::Bool),
            Some(Ty::Sym),
        ])))
        .unwrap();
        let params = fn_params(contract);
        assert_eq!(
            params.iter().map(|p| (*p.ty).clone()).collect::<Vec<_>>(),
            vec![Ty::Int, Ty::Str, Ty::Bool, Ty::Sym]
        );
    }

    #[test]
    fn mixed_arity_adds_nil_for_missing_positions() {
        let body = expr(
            ExprNode::Seq {
                exprs: vec![
                    yield_expr(vec![Some(Ty::Int), Some(Ty::Bool)]),
                    yield_expr(vec![Some(Ty::Str)]),
                ],
            },
            None,
        );
        let params = fn_params(for_method(&method(body)).unwrap());
        assert_eq!(
            *params[0].ty,
            crate::analyze::body::union_of(Ty::Int, Ty::Str)
        );
        assert_eq!(
            *params[1].ty,
            crate::analyze::body::union_of(Ty::Bool, Ty::Nil)
        );
    }

    #[test]
    fn preserves_unknown_argument_types() {
        let unknown = Ty::Var {
            var: crate::ident::TyVar(41),
        };
        let params =
            fn_params(for_method(&method(yield_expr(vec![Some(unknown.clone()), None]))).unwrap());
        assert_eq!(*params[0].ty, unknown);
        assert_eq!(*params[1].ty, Ty::Untyped);
    }

    #[test]
    fn refuses_splat_yield_argument() {
        let body = expr(
            ExprNode::Yield {
                args: vec![expr(
                    ExprNode::Splat {
                        value: expr(
                            ExprNode::SelfRef,
                            Some(Ty::Array {
                                elem: Arc::new(Ty::Int),
                            }),
                        ),
                    },
                    None,
                )],
            },
            None,
        );
        assert!(for_method(&method(body)).is_none());
    }
    #[test]
    fn unknown_tuple_is_not_erased_by_a_known_tuple() {
        let body = expr(
            ExprNode::Seq {
                exprs: vec![yield_expr(vec![None]), yield_expr(vec![Some(Ty::Int)])],
            },
            None,
        );
        let params = fn_params(for_method(&method(body)).unwrap());
        assert!(params[0].ty.mentions_unknown());
    }

    #[test]
    fn nested_method_yields_belong_to_their_own_frame() {
        let mut nested = expr(ExprNode::SelfRef, None);
        nested.set_nested_def(method(yield_expr(vec![Some(Ty::Str), Some(Ty::Bool)])));
        let body = expr(
            ExprNode::Seq {
                exprs: vec![yield_expr(vec![Some(Ty::Int)]), nested],
            },
            None,
        );
        let params = fn_params(for_method(&method(body)).unwrap());
        assert_eq!(params.len(), 1);
        assert_eq!(*params[0].ty, Ty::Int);
    }
}
