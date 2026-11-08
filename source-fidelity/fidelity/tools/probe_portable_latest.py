#!/usr/bin/env python3
"""Compile-only whole-method latest closure; no failed output is executed.

Shared/native settings are proved separately. This measurement preserves every
selected original method body/option branch; it is not a hand-written backend,
full default_results/list_latest or page acceptance.
"""
import argparse
import json
import os
import shutil

from probe_core_no_plugins import CoreNoPluginsRun
from probe_original_query import audit_projection, diagnostics
from verify import ROOT, HERE, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helpers", action="store_true", help="include complete pinned list/poster/lookup helpers; compile-only")
    parser.add_argument("--read-models", action="store_true", help="add source read-model projections and actual readonly catalog schema; compile-only")
    parser.add_argument("--candidate-models", action="store_true", help="with read models, use separately manifested authorized candidate model sources")
    parser.add_argument("--native-settings-interface", action="store_true", help="include source-declared interface for the real native scalar module; supplies NO implementation/values")
    parser.add_argument("--identity-interface", action="store_true", help="annotate supported User-or-nil identity fields; supplies NO identity/permissions")
    parser.add_argument("--services", action="store_true", help="include actual remaining service method closures; compile-only")
    parser.add_argument("--read-model-interface", action="store_true", help="include source-derived valid User/lookup method contracts; no identity values")
    parser.add_argument("--native-diagnostic", action="store_true", help="compile-only actual latest entry after strict admission; NEVER executes it")
    args = parser.parse_args()
    if args.candidate_models or args.services:
        args.read_models = True
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = CoreNoPluginsRun()
    run.evidence.update(profile="PATCHED shared settings next whole-method latest dependency measurement ONLY",
                        native_query_accepted=False, core_latest_accepted=False)
    try:
        run.provenance()
        run.initial_reference()
        app = run.path / "latest-method-input"
        run.command("project-latest-methods", ["ruby", HERE / "tools/project_core_latest.rb", HERE / "source/discourse", app], timeout=30)
        (app / "db").mkdir(exist_ok=True)
        if args.read_models:
            from latest_model_schema import schema
            schema_text = schema(run)
        else:
            schema_text = run.schema()
        (app / "db/schema.rb").write_text(schema_text)
        (app / "config").mkdir(exist_ok=True)
        (app / "config/routes.rb").write_text("Rails.application.routes.draw do\nend\n")
        # Same truthful backend declaration as the established readonly probes.
        # Without it the compiler emits SQLite Db, not the PG API in ENTRY.
        (app / "config/database.yml").write_text("test:\n  adapter: postgresql\n  database: discourse_development\n")
        if args.helpers or args.read_models:
            from latest_dependencies import materialize
            materialize(app, read_models=args.read_models, services=args.services, fresh_flag_reads=args.candidate_models)
            run.evidence["complete_helper_inputs_included"] = True
        if args.read_models:
            argv = ["ruby", HERE / "tools/project_latest_models.rb", HERE / "source/discourse", app]
            if args.candidate_models:
                argv.append(HERE / "compat/discourse")
            run.command("project-latest-read-models", argv, timeout=30)
        if args.candidate_models:
            from latest_candidate_helpers import materialize as materialize_candidate_helpers
            materialize_candidate_helpers(app)
            run.evidence["shared_readonly_flag_view"] = {"distributed_flag_read_cache_equivalence": False,
                "queries_and_instance_memoization_preserved": True}
        if args.candidate_models:
            run.command("project-latest-read-api-roots", ["ruby", HERE / "tools/project_latest_read_roots.rb",
                HERE / "source/discourse", app, HERE / "compat/discourse"], timeout=30)
            run.command("project-latest-custom-field-reads", ["ruby", HERE / "tools/project_latest_custom_fields.rb",
                HERE / "source/discourse", app], timeout=30)
            run.evidence["list_helper_scope"] = "list_latest read roots and static whole-method closure; not inherited serializable_hash/unused helper API acceptance"
        if args.services:
            argv = ["ruby", HERE / "tools/project_latest_services.rb", HERE / "source/discourse", app]
            if args.candidate_models:
                argv.append(HERE / "compat/discourse")
            run.command("project-latest-services", argv, timeout=30)
        if args.native_settings_interface:
            manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
            name = "discourse/sig/portable_scalar_readers.rbs"
            source = HERE / "compat" / name
            assert digest(source.read_bytes()) == manifest["candidate_source_sha256"][name]
            target = app / "sig/portable_scalar_readers.rbs"
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, target)
            run.evidence["external_native_settings_interface"] = {"source": name, "sha256": digest(source.read_bytes()),
                "supplies_values_or_implementation": False, "runtime_module_required_before_any_execution": True,
                "scope": "existing source-derived mixin, independently executed on native; not observed effective types"}
        if args.read_model_interface:
            name = "discourse/sig/portable_read_model_params.rbs"
            manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
            source = HERE / "compat" / name
            assert digest(source.read_bytes()) == manifest["candidate_source_sha256"][name]
            target = app / "sig/portable_read_model_params.rbs"
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, target)
            run.evidence["read_model_parameter_contract"] = {"source": name, "sha256": digest(source.read_bytes()),
                "supplies_identity_or_permissions": False, "runtime_execution_accepted": False}
        if args.identity_interface:
            name = "discourse/sig/portable_query_identities.rbs"
            manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
            source = HERE / "compat" / name
            assert digest(source.read_bytes()) == manifest["candidate_source_sha256"][name]
            target = app / "sig/portable_query_identities.rbs"
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, target)
            run.evidence["query_identity_field_contract"] = {"source": name, "sha256": digest(source.read_bytes()),
                "supplies_identity_or_permissions": False, "native_identity_matrix_accepted": False}
        before = audit_projection(app)
        from compat_source_audit import audit
        candidate_before = audit(app)
        run.evidence["candidate_model_source_map"] = candidate_before
        run.evidence["whole_method_source_map"] = before
        run.evidence["latest_method_closure"] = json.loads((app / "latest-method-closure.json").read_text())
        compiler = ROOT / "roundhouse/target/release/roundhouse"
        run.evidence["compiler_sha256"] = digest(compiler.read_bytes())
        code, _ = run.command("latest-method-strict-emit", [compiler, "--target", "spinel", app, "-o", run.path / "latest-method-emitted"],
                              check=False, timeout=120)
        stderr = (run.path / "latest-method-strict-emit.stderr").read_text()
        run.evidence["strict_inventory"] = {"returncode": code, "diagnostics": diagnostics(stderr, app),
                                           "output_executed": False}
        if args.native_diagnostic:
            assert code == 0, "cannot compile failed lowerer output"
            from latest_native_diagnostic import diagnose
            diagnose(run, run.path / "latest-method-emitted")
        assert before == audit_projection(app)
        assert candidate_before == audit(app)
        run.provenance()
        run.evidence.update(status="latest_whole_method_dependencies_measured_ONLY", native_query_accepted=False,
                            core_latest_accepted=False)
    except Exception as error:
        run.evidence.update(status="failed_latest_whole_method_measurement", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()
