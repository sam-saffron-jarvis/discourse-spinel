#!/usr/bin/env python3
"""Project and execute the pinned original serializer bridge in a tiny consumer.

The three ApplicationController methods and the Guardian scope methods are
byte-exact Prism projections. The only custom application files are a small
ActiveModel::Serializer model used to exercise the pinned reusable gem, and a
consumer; they are not Discourse serializers or page evidence.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
AMS_VERSION = "0.8.4"
MULTI_JSON_VERSION = "1.21.2"

BRIDGE_ASSERTIONS = r'''require_relative "lib/guardian"
require_relative "app/controllers/application_controller"
require_relative "app/models/bridge_record"
require_relative "app/serializers/bridge_serializer"

def new_controller
  controller = ApplicationController.new
  # A real instance of the exact projected original Guardian initializer/user
  # methods. Its user is a nonblank opaque fixture actor; no authorization
  # method is called by this serializer fixture.
  controller.instance_variable_set(:@guardian, Guardian.new(Object.new))
  controller
end

def assert_response(controller, body, status)
  raise "response body: #{controller.body.inspect}" unless controller.body == body
  raise "response status: #{controller.status.inspect}" unless controller.status == status
  raise "response content type: #{controller.content_type.inspect}" unless controller.content_type == "application/json"
end

single = new_controller
single.render_serialized(BridgeRecord.new(23, "alpha"), BridgeSerializer)
assert_response(single, '{"bridge":{"id":23,"title":"alpha"}}', 200)

array = new_controller
array.render_serialized([BridgeRecord.new(23, "alpha"), BridgeRecord.new(24, "beta")], BridgeSerializer)
assert_response(array, '[{"id":23,"title":"alpha"},{"id":24,"title":"beta"}]', 200)

rest = new_controller
options = {
  rest_serializer: true,
  status: 207,
  refresh_topics: true,
  extras: {"reason" => "fixture"},
  meta: {"page" => 2},
}
rest.render_serialized(BridgeRecord.new(23, "alpha"), BridgeSerializer, options)
assert_response(rest, '{"bridge":{"id":23,"title":"alpha"},"__rest_serializer":"1","refresh_topics":true,"extras":{"reason":"fixture"},"meta":{"page":2}}', 207)
raise "render_json_dump mutated caller options" unless options[:status] == 207 && options[:rest_serializer] == true

puts "original serializer bridge passed"
'''

RECORD = '''class BridgeRecord
  attr_reader :id, :title

  def initialize(id, title)
    @id = id
    @title = title
  end

  def read_attribute_for_serialization(name)
    public_send(name)
  end
end
'''
SERIALIZER = '''class BridgeSerializer < ActiveModel::Serializer
  attributes :id, :title
end
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command_record(args: list[str], cwd: Path, env: dict[str, str] | None = None) -> tuple[int, str, str]:
    proc = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    return proc.returncode, proc.stdout, proc.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fidelity", type=Path, required=True)
    parser.add_argument("--original-repo", type=Path, required=True)
    parser.add_argument("--roundhouse", type=Path, required=True)
    parser.add_argument("--spinel", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fidelity = args.fidelity.resolve()
    original_repo = args.original_repo.resolve()
    roundhouse = args.roundhouse.resolve()
    spinel = args.spinel.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    input_root = output / "input"
    input_root.mkdir()
    lock = json.loads((fidelity / "SOURCE_LOCK.json").read_text())
    if lock.get("discourse_revision") != PIN:
        raise SystemExit("source lock revision mismatch")
    source_records = {item["path"]: item["sha256"] for item in lock["files"]}
    projected_paths = [
        "app/controllers/application_controller.rb",
        "lib/guardian.rb",
    ]
    for source_path in projected_paths:
        if source_path not in source_records:
            raise SystemExit(f"source lock is missing {source_path}")
        original = (fidelity / "source/discourse" / source_path).read_bytes()
        if digest(original) != source_records[source_path]:
            raise SystemExit(f"locked original source changed: {source_path}")
    gem_lock_hash = source_records.get("Gemfile.lock")
    pinned_gem_lock = (fidelity / "source/discourse/Gemfile.lock").read_bytes()
    if not gem_lock_hash or digest(pinned_gem_lock) != gem_lock_hash:
        raise SystemExit("pinned Gemfile.lock is absent from SOURCE_LOCK or has changed")
    original_lock = subprocess.run(
        ["git", "-C", str(original_repo), "show", f"{PIN}:Gemfile.lock"],
        check=True, capture_output=True,
    ).stdout
    if digest(original_lock) != gem_lock_hash:
        raise SystemExit("pinned repository Gemfile.lock differs from SOURCE_LOCK")
    lock_text = pinned_gem_lock.decode()
    if f"active_model_serializers ({AMS_VERSION})" not in lock_text:
        raise SystemExit("pinned lock does not resolve expected ActiveModel Serializers")
    if f"multi_json ({MULTI_JSON_VERSION})" not in lock_text:
        raise SystemExit("pinned lock does not resolve expected MultiJson")

    projected = subprocess.run(
        ["ruby", str(fidelity / "tools/project_original_serialization_bridge.rb"),
         str(fidelity / "source/discourse"), str(input_root)],
        text=True, capture_output=True,
    )
    (output / "projection.stdout").write_text(projected.stdout)
    (output / "projection.stderr").write_text(projected.stderr)
    if projected.returncode:
        return projected.returncode
    manifest = json.loads((input_root / "serialization-bridge-projection.json").read_text())
    for projection in manifest["projections"]:
        src = (fidelity / "source/discourse" / projection["source"]).read_bytes()
        emitted = (input_root / projection["generated"]).read_bytes()
        for span in projection["selected_spans"]:
            start, end = span["start_byte"], span["end_byte"]
            if src[start:end] != emitted[start:end] or digest(emitted[start:end]) != span["sha256"]:
                raise SystemExit(f"projected source span drift: {span['role']}")

    (input_root / "Gemfile.lock").write_bytes(pinned_gem_lock)
    (input_root / "Gemfile").write_text(
        'source "https://rubygems.org"\n'
        'gem "active_model_serializers", "~> 0.8.3"\n'
        'gem "multi_json"\n'
    )
    bundle_path = os.environ.get(
        "ORIGINAL_BUNDLE_PATH", "/home/agent/work/discourse-spinel/run/bundle"
    )
    (input_root / ".bundle").mkdir()
    (input_root / ".bundle/config").write_text(f'---\nBUNDLE_PATH: "{bundle_path}"\n')
    for path, body in {
        "app/models/bridge_record.rb": RECORD,
        "app/serializers/bridge_serializer.rb": SERIALIZER,
    }.items():
        dest = input_root / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body)

    emit_cmd = [str(roundhouse), "--target", "spinel", str(input_root), "-o", str(output / "emitted")]
    rc, stdout, stderr = command_record(emit_cmd, fidelity)
    (output / "roundhouse.stdout").write_text(stdout)
    (output / "roundhouse.stderr").write_text(stderr)
    evidence: dict[str, object] = {
        "source_revision": PIN,
        "gem_versions": {"active_model_serializers": AMS_VERSION, "multi_json": MULTI_JSON_VERSION},
        "gemfile_lock_sha256": gem_lock_hash,
        "projection": manifest,
        "roundhouse_command": emit_cmd,
        "roundhouse_returncode": rc,
        "spinel_path": str(spinel),
        "output_executed": False,
        "fixture_limit": "Reduced serializer/record fixture using real pinned AMS/MultiJson; not TopicListSerializer or page proof",
    }
    if rc:
        evidence["first_boundary"] = "Roundhouse refused or failed to emit the exact original bridge projection; inspect raw command logs"
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence, indent=2))
        return rc

    emitted = output / "emitted"
    contract = emitted / "contract.rb"
    contract.write_text('require_relative "boot"\n' + BRIDGE_ASSERTIONS)
    ruby_lib = subprocess.run(["ruby", "-e", "print Gem.path.join(\":\")"], text=True, capture_output=True, check=True).stdout
    env = os.environ.copy()
    env["GEM_HOME"] = bundle_path + "/ruby/4.0.0"
    env["GEM_PATH"] = bundle_path + "/ruby/4.0.0:" + ruby_lib
    env["BLOG_DB"] = ":memory:"
    cruby_cmd = ["ruby", "contract.rb"]
    cruby_rc, cruby_out, cruby_err = command_record(cruby_cmd, emitted, env)
    (output / "cruby.stdout").write_text(cruby_out)
    (output / "cruby.stderr").write_text(cruby_err)
    evidence.update({
        "cruby_command": cruby_cmd,
        "cruby_returncode": cruby_rc,
        "cruby_output": cruby_out,
        "native_compile_returncode": None,
        "native_run_returncode": None,
        "native_output": None,
    })
    if cruby_rc:
        evidence["first_boundary"] = "first execution failure in the same Spinel-target emitted Ruby under CRuby"
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence, indent=2))
        return cruby_rc

    native_compile = ["taskset", "-c", "4,5", str(spinel), "--jobs=2", "contract.rb", "-o", "contract"]
    native_rc, native_out, native_err = command_record(native_compile, emitted)
    (output / "native-compile.stdout").write_text(native_out)
    (output / "native-compile.stderr").write_text(native_err)
    evidence["native_compile_command"] = native_compile
    evidence["native_compile_returncode"] = native_rc
    if native_rc:
        evidence["first_boundary"] = "native compiler refusal/failure after same-lowered CRuby passed"
        evidence["native_stderr"] = native_err
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence, indent=2))
        return native_rc
    native_run = ["taskset", "-c", "4,5", "./contract"]
    native_run_rc, native_run_out, native_run_err = command_record(native_run, emitted)
    (output / "native-run.stdout").write_text(native_run_out)
    (output / "native-run.stderr").write_text(native_run_err)
    evidence.update({
        "native_run_command": native_run,
        "native_run_returncode": native_run_rc,
        "native_output": native_run_out,
        "output_executed": True,
        "first_boundary": None if native_run_rc == 0 else "native executable runtime failure after compilation",
    })
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({k: evidence[k] for k in (
        "roundhouse_returncode", "cruby_returncode", "native_compile_returncode",
        "native_run_returncode", "first_boundary", "output_executed",
    )}, indent=2))
    return native_run_rc


if __name__ == "__main__":
    raise SystemExit(main())
