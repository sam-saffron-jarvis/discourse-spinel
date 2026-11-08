//! Preserve source literal allocation policy with declaration/resource IR.
//! A frozen source literal is not a request to call String#freeze (which can
//! be overridden). Keep its file directive; never freeze observed values.

use crate::App;
use crate::dialect::{ConditionalDefinitions, LibraryClass};
use crate::expr::{Expr, ExprNode, Literal};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum Policy {
    #[default]
    Unspecified,
    Default,
    Frozen,
    Mixed,
}

impl Policy {
    pub fn from_source(text: &str) -> Self {
        if crate::ingest::expr::freezes_literals(text) {
            Self::Frozen
        } else {
            Self::Default
        }
    }

    pub fn join(self, other: Self) -> Self {
        match (self, other) {
            (Self::Unspecified, policy) | (policy, Self::Unspecified) => policy,
            (left, right) if left == right => left,
            _ => Self::Mixed,
        }
    }

    pub fn directive(self) -> &'static str {
        if self == Self::Frozen {
            "# frozen_string_literal: true\n"
        } else {
            ""
        }
    }
}

pub(crate) fn expression(app: &App, expr: &Expr) -> Policy {
    let mut policy = Policy::Unspecified;
    if matches!(
        &*expr.node,
        ExprNode::Lit {
            value: Literal::Str { .. }
        }
    ) && let Some(index) = expr.span.file.0.checked_sub(1)
        && let Some(source) = app.sources.get(index as usize)
    {
        policy = Policy::from_source(&source.text);
    }
    expr.node.for_each_child(&mut |child| {
        policy = policy.join(expression(app, child));
    });
    policy
}

fn conditions(app: &App, definitions: &ConditionalDefinitions) -> Policy {
    let mut policy = Policy::Unspecified;
    for arm in &definitions.arms {
        if let Some(condition) = &arm.condition {
            policy = policy.join(expression(app, condition));
        }
        for nested in &arm.nested {
            policy = policy.join(conditions(app, nested));
        }
    }
    policy
}

/// Group only actual source-backed static literals. Synthetic framework values
/// retain their existing policy. Mixed original files require per-expression
/// allocation IR, not a guessed common directive or an implicit freeze call.
pub(crate) fn declarations<'a>(app: &App, classes: impl IntoIterator<Item = &'a LibraryClass>) -> Policy {
    let mut policy = Policy::Unspecified;
    for class in classes {
        for method in &class.methods {
            policy = policy.join(expression(app, &method.body));
            for value in method.params.iter().filter_map(|param| param.default.as_ref()) {
                policy = policy.join(expression(app, value));
            }
        }
        for expr in class
            .constants
            .iter()
            .map(|(_, value)| value)
            .chain(&class.class_ivar_initializers)
            .chain(&class.unknown_calls)
        {
            policy = policy.join(expression(app, expr));
        }
        for definitions in &class.conditional_definitions {
            policy = policy.join(conditions(app, definitions));
        }
    }
    policy
}
