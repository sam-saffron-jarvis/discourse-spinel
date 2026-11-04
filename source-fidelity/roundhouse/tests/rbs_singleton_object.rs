//! RBS singleton values must preserve the class-object ABI through callable
//! fields and nested lexical scopes, never become nominal instance pointers.
use roundhouse::ty::Ty;
use roundhouse::{ClassId, Symbol};
#[test]
fn nested_singleton_parameters_and_callable_fields_keep_root_owner() {
    let source = "module RuntimeStore\n  class Entry\n    def invoke: (singleton(::Owner) receiver, ^(singleton(::Owner)) -> Integer body) -> singleton(::Owner)\n  end\nend\n";
    let signatures = roundhouse::rbs::parse_app_signatures(source).unwrap();
    let Ty::Fn { params, ret, .. } =
        &signatures[&ClassId(Symbol::from("RuntimeStore::Entry"))][&Symbol::from("invoke")]
    else {
        panic!("function signature")
    };
    let expected = Ty::Class {
        id: ClassId(Symbol::from("Class")),
        args: vec![Ty::Class {
            id: ClassId(Symbol::from("Owner")),
            args: vec![].into(),
        }]
        .into(),
    };
    assert_eq!(*params[0].ty, expected);
    assert_eq!(**ret, expected);
    let Ty::Fn {
        params: captured, ..
    } = &*params[1].ty
    else {
        panic!("typed callable")
    };
    assert_eq!(*captured[0].ty, expected);
}
#[test]
fn ordinary_instance_parameters_stay_instances() {
    let signatures = roundhouse::rbs::parse_app_signatures(
        "class Owner\n def value: (Owner input) -> Owner\nend\n",
    )
    .unwrap();
    let Ty::Fn { params, ret, .. } =
        &signatures[&ClassId(Symbol::from("Owner"))][&Symbol::from("value")]
    else {
        panic!("function signature")
    };
    let expected = Ty::Class {
        id: ClassId(Symbol::from("Owner")),
        args: vec![].into(),
    };
    assert_eq!(*params[0].ty, expected);
    assert_eq!(**ret, expected);
}
