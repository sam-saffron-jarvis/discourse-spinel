//! Contextual typing for a literal callable passed as an ordinary argument.
//! Its declaration supplies parameters, never a fabricated return/body type.
use super::*;

impl BodyTyper<'_> {
    pub(super) fn callable_argument_seeds(
        &self,
        recv: Option<&Ty>,
        method: &Symbol,
        index: usize,
        class_side: bool,
        argument: &Expr,
    ) -> Option<lambda_local::Seeds> {
        let ExprNode::Lambda {
            params: names,
            rest_param: None,
            extra_params,
            block_param: None,
            ..
        } = &*argument.node
        else {
            return None;
        };
        if !extra_params.is_empty() {
            return None;
        }
        let Ty::Class { id, args } = recv? else {
            return None;
        };
        let id = if id.0.as_str() == "Class"
            && let [Ty::Class { id, .. }] = args.as_slice()
        {
            id
        } else {
            id
        };
        let mut current = Some(id);
        for _ in 0..32 {
            let class = self.classes().get(current?)?;
            let lookup = if method.as_str() == "new" && !class.declares_constructor {
                Symbol::from("initialize")
            } else {
                method.clone()
            };
            let candidates = if class_side {
                [
                    class.class_methods.get(&lookup),
                    class.instance_methods.get(&lookup),
                ]
            } else {
                [
                    class.instance_methods.get(&lookup),
                    class.class_methods.get(&lookup),
                ]
            };
            for signature in candidates.into_iter().flatten() {
                let Ty::Fn { params, .. } = signature else {
                    continue;
                };
                let formal = params
                    .iter()
                    .filter(|param| {
                        matches!(
                            param.kind,
                            crate::ty::ParamKind::Required | crate::ty::ParamKind::Optional
                        )
                    })
                    .nth(index)?;
                let Ty::Fn {
                    params: expected, ..
                } = &*formal.ty
                else {
                    return None;
                };
                if expected.len() != names.len()
                    || expected.iter().any(|param| {
                        !matches!(param.kind, crate::ty::ParamKind::Required)
                            || param.ty.mentions_unknown()
                    })
                {
                    return None;
                }
                return Some(lambda_local::Seeds {
                    positional: expected
                        .iter()
                        .map(|param| {
                            Some(param.ty.subst_self(&Ty::Class {
                                id: id.clone(),
                                args: vec![].into(),
                            }))
                        })
                        .collect(),
                    keywords: Vec::new(),
                });
            }
            current = class.parent.as_ref();
        }
        None
    }
}

impl BodyTyper<'_> {
    pub(super) fn class_storage_access(
        &self,
        receiver: Option<&Ty>,
        method: &Symbol,
        args: &[Expr],
        class_object: bool,
    ) -> Option<Ty> {
        if !class_object
            || !matches!(
                method.as_str(),
                "instance_variable_get" | "instance_variable_set"
            )
        {
            return None;
        }
        let Ty::Class { id, args: generic } = receiver? else {
            return None;
        };
        let mut owner = if id.0.as_str() == "Class"
            && let [Ty::Class { id, .. }] = generic.as_slice()
        {
            id
        } else {
            id
        };
        let raw = match &*args.first()?.node {
            ExprNode::Lit {
                value: Literal::Sym { value },
            } => value.as_str(),
            ExprNode::Lit {
                value: Literal::Str { value },
            } => value.as_str(),
            _ => {
                let address = crate::analyze::class_storage_patterns::address(args.first()?)?;
                for _ in 0..32 {
                    let info = self.classes().get(owner)?;
                    if info.source_class_methods.contains(method) {
                        return None;
                    }
                    if let Some(pattern) = info.class_storage_patterns.iter().find(|pattern| {
                        (pattern.prefix.as_str(), pattern.suffix.as_str())
                            == (address.0.as_str(), address.1.as_str())
                    }) {
                        return match (method.as_str(), args) {
                            ("instance_variable_get", [_]) => Some(pattern.value.clone()),
                            ("instance_variable_set", [_, value]) => value.ty.clone(),
                            _ => None,
                        };
                    }
                    owner = info.parent.as_ref()?;
                }
                return None;
            }
        };
        let name = Symbol::from(raw.strip_prefix('@')?);
        for _ in 0..32 {
            let info = self.classes().get(owner)?;
            if info.source_class_methods.contains(method) {
                return None;
            }
            if let Some(ty) = info.class_instance_variables.get(&name) {
                return match (method.as_str(), args) {
                    ("instance_variable_get", [_]) => Some(ty.clone()),
                    ("instance_variable_set", [_, value]) => value.ty.clone(),
                    _ => None,
                };
            }
            owner = info.parent.as_ref()?;
        }
        None
    }
}
