#!/usr/bin/env python3
"""Bounded actual SeedFu producer/candidate-closure measurement; no admission."""
import argparse
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile

from verify import Run, ROOT, HERE, digest
from probe_original_query import diagnostics

MEMBERS = ["lib/discourse-seed-fu.rb"] + [f"lib/seed-fu/{name}.rb" for name in
    ("railtie", "version", "seeder", "active_record_extension", "block_hash", "runner", "writer")]


class SeedFuRun(Run):
    def __init__(self):
        super().__init__("probe-seedfu-closure")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4")
        self.evidence.update(stage="complete real SeedFu require/autoload CANDIDATE closure versus observed cold storage/initializer sources ONLY",
                             broader019_accepted=False, native_activation_accepted=False,
                             native_executed=False, native_seed_invoked=False, transformations=[])

    def build(self, compiler, source_gem_context=False):
        package = ROOT / "run/bundle/ruby/4.0.0/cache/discourse-seed-fu-2.3.12.gem"
        installed = ROOT / "run/bundle/ruby/4.0.0/gems/discourse-seed-fu-2.3.12"
        runtime_lock = (ROOT / "discourse/Gemfile.lock").read_bytes()
        assert re.search(rb"^    discourse-seed-fu \(2\.3\.12\)$", runtime_lock, re.M)
        self.command("gem-package-verify", ["ruby", "-rrubygems/package", "-e",
            'raise "invalid gem" unless Gem::Package.new(ARGV.fetch(0)).verify; puts "original package verified"', package], timeout=30)
        package_bytes = package.read_bytes()
        app = self.path / "input"
        maps = []
        with tarfile.open(fileobj=io.BytesIO(package_bytes), mode="r:*") as archive:
            data = archive.extractfile("data.tar.gz").read()
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            for name in MEMBERS:
                content = archive.extractfile(name).read()
                assert (installed / name).read_bytes() == content, "installed gem differs from verified package"
                generated = f"vendor/bundle/ruby/4.0.0/gems/discourse-seed-fu-2.3.12/{name}" if source_gem_context else name
                destination = app / generated
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
                maps.append({"package_member": name, "generated": generated, "sha256": digest(content),
                             "bytes": len(content), "complete_original": True})
        self.evidence["seedfu_package"] = {"path": str(package.relative_to(ROOT)), "sha256": digest(package_bytes),
            "runtime_lock_sha256": digest(runtime_lock), "installed_member_equality": True, "files": maps}
        for name, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n", "config/routes.rb": "Rails.application.routes.draw do\nend\n"}.items():
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        if source_gem_context:
            # Source layout/configuration only, never a substitute Railtie/body.
            metadata = {
                "roundhouse.yml": "extensions:\n  - config/roundhouse\n",
                "config/roundhouse/gems.yml": "source_gems:\n  - {gem: \"discourse-seed-fu\"}\n",
                "config/application.rb": "Bundler.require(*Rails.groups)\n",
                "Gemfile": 'source "https://rubygems.org"\ngem "discourse-seed-fu"\n',
                "Gemfile.lock": "GEM\n  remote: https://rubygems.org/\n  specs:\n    discourse-seed-fu (2.3.12)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  discourse-seed-fu\n\nBUNDLED WITH\n   2.6.9\n",
                ".bundle/config": '---\nBUNDLE_PATH: "vendor/bundle"\n',
            }
            for name, text in metadata.items():
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            self.evidence["candidate_context"] = {
                "kind": "source-gem file-program input, complete original members unchanged",
                "metadata_scope": "reduced compiler context ONLY, not complete original Rails application",
                "metadata_hashes": {name: digest((app / name).read_bytes()) for name in metadata},
                "railtie_body_replaced": False, "initializer_replayed": False,
            }
        code, _ = self.command("strict", [compiler, "--target", "spinel", app, "-o", self.path / "emitted"], check=False, timeout=120)
        self.evidence["strict_measurement"] = {"returncode": code,
            "diagnostics": diagnostics((self.path / "strict.stderr").read_text(), app),
            "warning": "zero errors would NOT establish required Railtie initializer effects; no emitted/error output is compiled or executed"}
        self.evidence["source_obligations"] = [
            "source-positioned original mattr storage installation and explicit @@ writes; no nil-seed reordering waiver",
            "required original SeedFu::Railtie initializer, not a fabricated Rails::Railtie class or default array",
            "lazy autoload/feature-cache/body-effect timing (default native eager autoload is documented subset behavior)",
            "actual register_seedfu_fixtures producer appends and original environment/root inputs",
            "GzipReader is in an unexecuted autoload candidate (Runner), NOT an observed cold fixture-path dependency; retain its diagnostic without a blanket class admission or seed invocation"]
        self.save()

    def oracle_arguments(self):
        return [HERE / "tools/seedfu_source_oracle.rb", HERE / "tools/seedfu_source_oracle_consumer.rb", HERE / "test/seedfu_source_probe.rb"]

    def compare_oracle(self, oracle):
        text = (self.path / "rails-oracle.stdout").read_text()
        traces = [json.loads(line.removeprefix("FIDELITY_SEEDFU_TRACE ")) for line in text.splitlines() if line.startswith("FIDELITY_SEEDFU_TRACE ")]
        assert len(traces) == 1 and traces[0]["successful_oracle"]
        trace = traces[0]
        if self.env.get("FIDELITY_TEST_VIPS_RETITLE") == "1":
            assert trace["vips_retitle_control"], "retitled original worker control did not execute"
        assert any(event["source"][0].endswith("/seed-fu/railtie.rb") and event["event"] == "b_call" for event in trace["events"]), "real fixture-path initializer was not observed"
        assert len(oracle) == 1 and oracle[0]["same_storage"]
        producer_sources = {}
        pin = self.evidence["source_revision"]
        for event in trace["events"]:
            for path, _ in event.get("original_callers", []):
                relative = Path(path).relative_to(ROOT / "discourse")
                original = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{pin}:{relative}"])
                assert (ROOT / "discourse" / relative).read_bytes() == original
                producer_sources[str(relative)] = digest(original)
        self.evidence["actual_seedfu_source_observation"] = {"trace": trace, "records": oracle,
            "original_accessor_and_producer_caller_hashes": producer_sources,
            "not_native_inputs": True, "default_array_is_not_initialized_state": oracle[0]["paths"] != ["db/fixtures"]}
        return {"scope": "observation ONLY, no native/compat parity or SeedFu admission", "native_equal": False, "compat_equal": False}

    def audit(self):
        report = self.evidence["seedfu_package"]
        assert digest((ROOT / report["path"]).read_bytes()) == report["sha256"]
        assert digest((ROOT / "discourse/Gemfile.lock").read_bytes()) == report["runtime_lock_sha256"]
        for item in report["files"]:
            assert digest((self.path / "input" / item["generated"]).read_bytes()) == item["sha256"]
        self.provenance()
        sandbox = self.evidence.get("oracle_sandbox")
        if sandbox:
            assert sandbox["status"] == "stopped" and sandbox["cleanup"] == "child_exited"
            self.evidence["oracle_cleanup_verified"] = True
        self.evidence["post_source_hashes_verified"] = True
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "roundhouse/target/release/roundhouse")
    parser.add_argument("--vips-retitle-control", action="store_true", help="observation-only delay after the original private worker start to verify ownership survives its original setproctitle")
    parser.add_argument("--source-gem-context", action="store_true", help="measure complete original gem members as source-gem features rather than eager app support declarations")
    args = parser.parse_args()
    import os
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = SeedFuRun()
    if args.vips_retitle_control:
        run.env["FIDELITY_TEST_VIPS_RETITLE"] = "1"
    try:
        run.provenance()
        run.build(args.compiler.resolve(), args.source_gem_context)
        try:
            run.oracle()
        finally:
            run.audit()
        run.evidence["status"] = "measured_unadmitted_seedfu_closure_NOT_activation"
        run.save()
        print(f"MEASURED ONLY; SeedFu/native activation/019 NOT ADMITTED. Evidence: {run.path}")
        return 0
    except Exception as error:
        import traceback
        traceback.print_exc()
        run.evidence.update(status="failed_measurement", error=repr(error))
        run.save()
        print(f"NOT PASSED: {error}\nEvidence: {run.path}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
