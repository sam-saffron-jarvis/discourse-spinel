#!/usr/bin/env python3
"""Actual import-map template prefix through owned real V8/compiler-version cache, NOT page."""
import json
import os
import re
import shutil
from pathlib import Path
from probe_list_layout_stage import ListLayoutStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest, Run

COMPILER_FILES = ("list_compiler_source.rb", "native_importmap_prefix.rb", "original_importmap_prefix.rb", "native_importmap_registry.rb", "original_importmap_registry.rb", "importmap_nonce_source.rb", "original_compiler_helpers.rb", "layout_asset_processor_backend.rb", "list_compiler_context.rb", "list_compiler_original_context.rb", "original_theme_js_prefix.rb")

class ImportMapCompilerStageRun(ListLayoutStageRun):
    success_status = "PASS_IMPORTMAP_PREFIX_REAL_V8_COMPILER_VERSION_CACHE"
    allow_array_cache = False
    allow_field_cache = False
    allow_svg_theme_cache = False
    field_cache_key_pattern = r"-?[0-9]+:translations:[A-Za-z_-]+:[a-f0-9]{40}"

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("generate-importmap-compiler-prefix", ["bundle", "exec", "ruby", HERE / "tools/generate_importmap_compiler_prefix.rb", app, self.path], cwd=ROOT / "discourse")
        self.evidence["compiler_prefix_source"] = json.loads((self.path / "importmap-compiler-source-proof.json").read_text())

    def generate(self):
        super().generate()
        # Existing tested source bridge artifact, not an engine result/URL/payload.
        adapter_sha = digest((HERE / "test/layout_asset_processor_native.cc").read_bytes())
        def matching_bridge():
            paths = sorted((HERE / "build").glob("native-asset-vm-*/evidence.json"), key=lambda p: p.stat().st_mtime, reverse=True)
            for path in paths:
                item = json.loads(path.read_text())
                library = item.get("native_library", {})
                if item.get("status") == "PASS_SCOPED_RUBY_FREE_ORIGINAL_V8_VERSION_COMPONENT" and item.get("adapter_sha256") == adapter_sha and library and Path(library["path"]).exists() and digest(Path(library["path"]).read_bytes()) == library["sha256"]:
                    return item
            return None
        bridge = matching_bridge()
        if bridge is None:
            self.command("build-native-vm-capability", ["bundle", "exec", "ruby", HERE / "tools/probe_layout_asset_processor_native.rb"], cwd=ROOT / "discourse", timeout=240)
            bridge = matching_bridge()
        assert bridge is not None, "matching tested source VM capability unavailable"
        library = bridge["native_library"]
        assert digest(Path(library["path"]).read_bytes()) == library["sha256"]
        assert digest((HERE / "test/layout_asset_processor_native.cc").read_bytes()) == bridge["adapter_sha256"]
        self.env.update(FIDELITY_VM_LIBRARY=library["path"], FIDELITY_VM_LIBRARY_SHA256=library["sha256"])
        self.evidence["native_vm_library"] = library
        self.evidence["vm_platform_drivers"] = {"native": digest((HERE / "test/layout_asset_processor_backend.rb").read_bytes()),
            "cruby": digest((HERE / "test/layout_asset_processor_cruby_backend.rb").read_bytes()),
            "application_context": digest((HERE / "test/list_compiler_context.rb").read_bytes()),
            "platform_difference": "PG driver + VM driver only; no replacement application/oracle payload"}
        for name in COMPILER_FILES:
            source = HERE / "test" / name
            if source.exists():
                shutil.copyfile(source, self.path / name)
        entry = self.path / "entry.rb"
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_compiler_context"\nCategoryCacheBootstrap.configure('))

    def normalize_stage_record(self, row):
        view = row["template_prefix"]
        nonce = view.pop("csp_nonce")
        assert isinstance(nonce, str) and re.fullmatch(r"[A-Za-z0-9]{25}", nonce)
        # ONLY nondeterministic original SecureRandom nonce is normalized in the
        # comparison, never runtime output. Raw stdout/prefixes remain retained.
        for key in ("incomplete_capture", "layout_partial_prefix"):
            assert view[key].count(nonce) == 1
            view[key] = view[key].replace(nonce, "[genuine-random-nonce]")
        return row

    def verify_continuation(self):
        super().verify_continuation()
        values = [lifecycle(self, n)["theme_compiler_cache"] for n in ("native", "compat", "compat-original")]
        assert values[0] == values[1] == values[2] and "compiler_version" in values[0] and isinstance(values[0]["compiler_version"], str)
        if self.allow_array_cache:
            assert all(k == "compiler_version" or re.fullmatch(r"[-0-9,]+:extra_js:[a-f0-9]{40}", k) and isinstance(v, list) or self.allow_field_cache and re.fullmatch(self.field_cache_key_pattern, k) and (v is None or isinstance(v, list) and all(isinstance(item, str) for item in v)) or self.allow_svg_theme_cache and (re.fullmatch(r"settings_for_theme_-?[0-9]+_(?:true|false)", k) and isinstance(v, dict) and not v or re.fullmatch(r"-?[0-9]+(?:,-?[0-9]+)*:modifier:svg_icons:[a-f0-9]{40}", k) and isinstance(v, list) and all(isinstance(item, str) for item in v)) for k, v in values[0].items())
        else:
            assert set(values[0]) == {"compiler_version"}
        controls = {}
        for fault, expected in (("missing-compiler-publication", "missing category cache publication"), ("wrong-vm-owner", "VM source fixture ownership")):
            self.env["FIDELITY_COMPILER_FAULT"] = fault
            for runtime, argv in (("native", [self.path / "probe"]), ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
                name = runtime + "-compiler-" + fault
                code, _ = self.command(name, argv, check=False, timeout=120)
                assert code != 0 and expected in (self.path / (name + ".stderr")).read_text(), name
                lifecycle(self, name)
                assert self.evidence["owned_cache_cleanup"][name] and self.evidence["owned_vm_source_cleanup"][name]
                controls[name] = {"returncode": code, "expected_error": expected, "fixtures_cleaned": True}
        del self.env["FIDELITY_COMPILER_FAULT"]
        self.evidence["compiler_controls"] = controls
        self.evidence.update(acquired_theme_compiler_values=values[0], real_v8_in_request_prefix=True,
            nonce_comparison_normalization="only validated actual random nonce in retained raw observation")

    def command(self, name, argv, **kwargs):
        if name.startswith("compat"):
            tree = self.path / ("compat-preflight" if name == "compat-preflight" else "compat")
            if tree.exists():
                for item in COMPILER_FILES:
                    shutil.copyfile(self.path / item, tree / item)
                shutil.copyfile(HERE / "test/layout_asset_processor_cruby_backend.rb", tree / "layout_asset_processor_backend.rb")
        if name == "compat-original":
            entry = self.path / "compat/entry-original.rb"
            entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "list_layout_original_context"\nrequire_relative "list_compiler_original_context"\nCategoryCacheBootstrap.configure('))
        binary = str(self.path / "probe")
        runtime = name.startswith("compat") or name != "native-compile" and binary in [str(x) for x in argv]
        if runtime:
            fixture = self.path / (name + "-vm-source")
            prior = self.env.get("FIDELITY_VM_SOURCE_ROOT")
            try:
                Run.command(self, "vm-source-" + name, ["bundle", "exec", "ruby", HERE / "tools/materialize_layout_vm_source.rb", ROOT / "discourse", fixture], cwd=ROOT / "discourse", timeout=30)
                self.env["FIDELITY_VM_SOURCE_ROOT"] = str(fixture)
                return super().command(name, argv, **kwargs)
            finally:
                if prior is None: self.env.pop("FIDELITY_VM_SOURCE_ROOT", None)
                else: self.env["FIDELITY_VM_SOURCE_ROOT"] = prior
                if fixture.exists(): shutil.rmtree(fixture)
                self.evidence.setdefault("owned_vm_source_cleanup", {})[name] = not fixture.exists()
        return super().command(name, argv, **kwargs)

if __name__ == "__main__":
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    execute(ImportMapCompilerStageRun())
