//! Explicit compile-only boundaries for survey projects. These are not
//! support claims: each boundary produces an error diagnostic and named raises.
use crate::App;
use crate::diagnostic::Diagnostic;
use crate::dialect::MethodReceiver;
use crate::expr::{Expr, ExprNode, Literal};
use crate::ident::Symbol;
use crate::ty::Ty;

/// Spinel does not represent OpenStruct subclasses. In an explicitly opted-in
/// survey project keep the class name, but make construction and every source
/// method fail with the native-superclass gap instead of inventing behavior.
/// Normal/strict/Ruby emission never calls this function.
pub fn native_subclass_boundaries(app: &mut App) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    for class in &mut app.library_classes {
        if class.parent.as_ref().is_none_or(|p| p.0.as_str() != "OpenStruct") { continue; }
        let detail = format!("class {} < OpenStruct", class.name.0);
        let message = format!("roundhouse: {detail}: subclassing OpenStruct not supported (spinel survey boundary)");
        diagnostics.push(Diagnostic::unsupported(class.parent_span, Some(Symbol::from("spinel")), "OpenStruct subclass", detail));
        let raised = || {
            let mut expr = Expr::new(class.parent_span, ExprNode::Raise {
                value: Expr::new(class.parent_span, ExprNode::Lit { value: Literal::Str { value: message.clone() } }),
            });
            expr.ty = Some(Ty::Bottom);
            expr
        };
        class.parent = None;
        for method in &mut class.methods { method.body = raised(); }
        let template = format!("class SurveyBoundary\n def self.new(*args, **kwargs, &block)\n raise {message:?}\n end\n def self.allocate\n raise {message:?}\n end\nend\n");
        let mut methods = crate::ingest::ingest_library_classes(template.as_bytes(), "roundhouse survey boundary")
            .expect("fixed survey boundary syntax").remove(0).methods;
        class.methods.retain(|m| !(m.receiver == MethodReceiver::Class && matches!(m.name.as_str(), "new" | "allocate")));
        for method in &mut methods { method.body = raised(); }
        class.methods.extend(methods);
    }
    diagnostics
}
