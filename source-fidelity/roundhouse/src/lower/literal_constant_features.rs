//! A source-gem file consisting solely of `module Owner; NAME = 'literal'; end`
//! is a constant feature, not a second callable Owner declaration. Keep its
//! original feature identity and assignment position. No general reopen merge,
//! computed value, namespace alias, callback or application-body passthrough.

use crate::app::ProgramItem;
use crate::dialect::LibraryClass;
use crate::expr::{Expr, ExprNode, LValue, Literal};
use crate::ingest::prism_api::PrismLocation;
use crate::span::{FileId, SourceFile, Span};
use crate::{App, ClassId, Symbol};

struct Definition {
    owner: ClassId,
    name: Symbol,
    value: String,
    write: Span,
    value_span: Span,
    mutable: bool,
}

fn definition(source: &SourceFile, file: FileId) -> Option<Definition> {
    // Read-only source proof; does not register another ingest or mutate IR.
    let parsed = ruby_prism::parse(source.text.as_bytes());
    if parsed.errors().next().is_some() {
        return None;
    }
    let root = parsed.node();
    let program = root.as_program_node()?;
    let statements: Vec<_> = program.statements().body().iter().collect();
    if statements.len() != 1 {
        return None;
    }
    let module = statements[0].as_module_node()?;
    let path = module.constant_path();
    let owner = path.as_constant_read_node()?; // Root, simple namespace only.
    let body = module.body()?.as_statements_node()?;
    let statements: Vec<_> = body.body().iter().collect();
    if statements.len() != 1 {
        return None;
    }
    let write = statements[0].as_constant_write_node()?;
    let value = write.value();
    let string = value.as_string_node()?;
    let span = |node: &ruby_prism::Node<'_>| Span {
        file,
        start: node.location().start_offset() as u32,
        end: node.location().end_offset() as u32,
    };
    Some(Definition {
        owner: ClassId(Symbol::from(std::str::from_utf8(owner.name().as_slice()).ok()?)),
        name: Symbol::from(std::str::from_utf8(write.name().as_slice()).ok()?),
        value: String::from_utf8(string.unescaped().to_vec()).ok()?,
        write: span(&statements[0]),
        value_span: span(&value),
        mutable: !crate::ingest::expr::freezes_literals(&source.text),
    })
}

fn source_definition(app: &App, source: &str) -> Option<Definition> {
    let (index, file) = app.sources.iter().enumerate().find(|(_, file)| file.path == source)?;
    definition(file, FileId(index as u32 + 1))
}

fn matches_class(class: &LibraryClass, definition: &Definition) -> bool {
    class.is_module
        && class.origin.is_none()
        && class.parent.is_none()
        && class.includes.is_empty()
        && class.methods.is_empty()
        && class.class_ivar_initializers.is_empty()
        && class.unknown_calls.is_empty()
        && class.conditional_definitions.is_empty()
        && class.constants.len() == 1
        && class.name == definition.owner
        && class.constants[0].0 == definition.name
        && class.constants[0].1.span == definition.value_span
        && matches!(&*class.constants[0].1.node, ExprNode::Lit { value: Literal::Str { value } } if value == &definition.value)
}

fn matches_write(expr: &Expr, definition: &Definition) -> bool {
    matches!(&*expr.node, ExprNode::Assign { target: LValue::Const { path }, value }
        if expr.span == definition.write && value.span == definition.value_span
            && path == &[definition.owner.0.clone(), definition.name.clone()]
            && matches!(&*value.node, ExprNode::Lit { value: Literal::Str { value } } if value == &definition.value))
}

fn matches_program(program: &crate::app::FileProgram, definition: &Definition) -> bool {
    match program.items.as_slice() {
        [ProgramItem::Declared(names)] => names == &[definition.owner.clone()],
        [ProgramItem::Opened(chains), ProgramItem::Statement(expr)] => {
            chains == &vec![vec![(definition.owner.0.as_str().to_string(), false)]] && matches_write(expr, definition)
        }
        _ => false, // Never drop a post-ingest/opaque file effect.
    }
}

/// Only source-gem FilePrograms select this profile. App lib/ declarations keep
/// their existing ordering/refusal; merely adding a source file is not proof.
/// One separate callable module owner must remain; this is not core namespace
/// creation or arbitrary constant-only declaration elimination.
pub(crate) fn is_feature_reopen(app: &App, class: &LibraryClass) -> bool {
    !app.library_classes.iter().any(|other| {
        other.name.0.as_str() == "String" && other.methods.iter().any(|method| method.name.as_str() == "+@")
    }) && app
        .library_classes
        .iter()
        .filter(|other| {
            other.name == class.name
                && other.is_module
                && (!other.methods.is_empty() || !other.class_ivar_initializers.is_empty())
        })
        .count()
        == 1
        && app.file_programs.iter().any(|program| {
            source_definition(app, &program.source)
                .is_some_and(|definition| matches_class(class, &definition) && matches_program(program, &definition))
        })
}

/// Preserve the typed constant record during analysis, but carry its actual
/// assignment in its original file program rather than in a merged owner file.
pub(crate) fn position(app: &mut App) {
    let definitions: Vec<_> = app
        .file_programs
        .iter()
        .enumerate()
        .filter_map(|(index, program)| {
            let definition = source_definition(app, &program.source)?;
            app.library_classes
                .iter()
                .any(|class| matches_class(class, &definition) && is_feature_reopen(app, class))
                .then_some((index, definition))
        })
        .collect();
    for (index, definition) in definitions {
        let mut value = app
            .library_classes
            .iter()
            .find(|class| matches_class(class, &definition) && is_feature_reopen(app, class))
            .unwrap()
            .constants[0]
            .1
            .clone();
        // Constant RHS ingest does not visit the assignment wrapper that
        // normally preserves Ruby's mutable String allocation. Reuse its
        // source magic-comment policy and shared expression hint here.
        if definition.mutable && value.hint().is_none() {
            value.set_hint(Some(crate::expr::IrHint::MutableStringLiteral));
        }
        app.file_programs[index].items = vec![
            ProgramItem::Opened(vec![vec![(definition.owner.0.as_str().to_string(), false)]]),
            ProgramItem::Statement(Expr::new(
                definition.write,
                ExprNode::Assign {
                    target: LValue::Const {
                        path: vec![definition.owner.0.clone(), definition.name],
                    },
                    value,
                },
            )),
        ];
    }
}

/// Emission of every target uses this same lowered feature IR. The original
/// constant stays available to analysis, never to an eager owner-file emitter.
pub(crate) fn lower(app: &App) -> Option<App> {
    if !app.library_classes.iter().any(|class| is_feature_reopen(app, class)) {
        return None;
    }
    let mut lowered = app.clone();
    position(&mut lowered);
    lowered.library_classes.retain(|class| !is_feature_reopen(app, class));
    Some(lowered)
}

/// A finite autoload binding may name this exact literal definition only.
/// Recheck source and RHS, not just a constant-assignment-shaped IR node.
pub(crate) fn binding(app: &App, source: &str, expr: &Expr) -> Option<ClassId> {
    let definition = source_definition(app, source)?;
    matches_write(expr, &definition)
        .then(|| ClassId(Symbol::from(format!("{}::{}", definition.owner.0, definition.name))))
}
