#!/usr/bin/env python3
"""UNIT-only tuple producers on genuine original/shared/native owned bulk cache."""
import json
import os
import shutil
from pathlib import Path
from theme_bulk_capability import ThemeBulkCapabilityRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

class ThemeBulkLifecycleRun(ThemeBulkCapabilityRun):
    def generate(self):
        super().generate()
        shutil.copyfile(HERE/'test/theme_bulk_unit.rb', self.path/'probe.rb')
        source = self.path/'theme_bulk_cache_source.rb'
        text = source.read_text()
        text = text.replace('hash.key?(key_blk.call(k))', '(hash.key?(key_blk.call(k)) && (ENV.fetch("FIDELITY_BULK_FAULT", "") != "nil-hit-as-miss" || !self[key_blk.call(k)].nil?))')
        text = text.replace('yield missing_keys.freeze', 'yield(ENV.fetch("FIDELITY_BULK_FAULT", "") == "unfrozen-missing" ? missing_keys : missing_keys.freeze)')
        text = text.replace('ks.zip(missing_hash.merge(found_hash).values_at(*ks)).to_h', '(ENV.fetch("FIDELITY_BULK_FAULT", "") == "reverse-return" ? ks.reverse : ks).zip(missing_hash.merge(found_hash).values_at(*ks)).to_h')
        source.write_text(text)
        bus = self.path/'category_cache_bus_source.rb'
        text = bus.read_text().replace('def set(hash, key, value);', 'def set(hash, key, value); return if ENV.fetch("FIDELITY_BULK_FAULT", "") == "omit-nil-publication" && value.nil?;')
        text = text.replace('def []=(k, v);', 'def []=(k, v); raise "bulk deferred assignment exception" if ENV.fetch("FIDELITY_BULK_FAULT", "") == "job-exception" && CategoryCacheBootstrap.lease.theme_field_key?(k);')
        bus.write_text(text)


def execute():
    run = ThemeBulkLifecycleRun()
    try:
        run.provenance()
        run.generate()
        run.command('native-compile', [ROOT/'spinel/spinel', '--jobs=4', '--int-overflow=promote', '--rbs', run.path/'emitted', '-I', Path.home()/'.cache/spin/packages/pg-0.2.0', run.path/'entry.rb', '-o', run.path/'probe'])
        run.command('native', ['strace', '-f', '-e', 'trace=execve,connect', '-o', run.path/'native.trace', run.path/'probe'], timeout=120)
        compat = run.path/'compat'
        shutil.copytree(run.path/'emitted', compat/'emitted')
        for name in ('entry.rb','probe.rb'): shutil.copyfile(run.path/name, compat/name)
        shutil.copyfile(ROOT/'roundhouse/runtime/spinel/pg_driver_cruby.rb', compat/'emitted/runtime/pg_driver.rb')
        run.command('compat', ['bundle','exec','ruby','--enable-frozen-string-literal',compat/'entry.rb'], timeout=120)
        # Same isolated original cache/worker/manager reference as cumulative
        # path; never a Rails HTML invocation or a substituted cache graph.
        run.command('generate-original-html-methods', ['ruby', HERE/'tools/generate_html_stage_original_methods.rb', compat/'original_html_stage_methods.rb'])
        entry = compat/'entry-original.rb'
        text = (compat/'entry.rb').read_text()
        text = text.replace('require_relative "latest_html_stage_transport"', 'require_relative "latest_html_stage_transport"\nrequire_relative "original_html_stage_methods"')
        entry.write_text(text)
        run.command('compat-original', ['bundle','exec','ruby','--enable-frozen-string-literal',entry], timeout=120)
        observations = []
        for name in ('native','compat','compat-original'):
            items = [json.loads(line.split(' ',1)[1]) for line in (run.path/(name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_THEME_BULK_UNIT ')]
            assert len(items) == 1
            observations.append(items[0])
            record = lifecycle(run,name)
            assert record['queued'] == record['finished'] and record['errors'] == 0 and record['pending'] == 0
            assert record['publications'] == record['expected_publications'] and record['publications'] > 0
            assert record['field_bulk_jobs'] == 3 and record['field_bulk_members'] == 3
        assert observations[0] == observations[1] == observations[2]
        controls = {}
        cases = [('FIDELITY_BULK_FAULT','nil-hit-as-miss','genuine bulk nil/warm hit recomputed'), ('FIDELITY_BULK_FAULT','unfrozen-missing','bulk missing slice is not frozen'), ('FIDELITY_BULK_FAULT','reverse-return','bulk result tuple order changed'), ('FIDELITY_BULK_FAULT','omit-nil-publication','missing category cache publication'), ('FIDELITY_BULK_FAULT','job-exception','bulk deferred assignment exception'), ('FIDELITY_CACHE_FAULT','shared-endpoint','protected/unknown cache endpoint'), ('FIDELITY_CACHE_FAULT','wrong-runtime','category cache runtime ownership')]
        for variable, fault, expected in cases:
            run.env[variable] = fault
            try:
                for runtime, argv in (('native',[run.path/'probe']),('compat',['bundle','exec','ruby',compat/'entry.rb'])):
                    name = runtime+'-bulk-'+fault
                    code,_ = run.command(name,argv,check=False,timeout=120)
                    assert code != 0 and expected in (run.path/(name+'.stderr')).read_text(), (name,code)
                    lifecycle(run,name)
                    assert all(run.evidence[key][name] for key in ('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name] = {'returncode':code, 'expected_error':expected, 'all_fixtures_cleaned':True}
            finally: del run.env[variable]
        run.evidence.update(status='PASS_UNIT_SOURCE_THEME_BULK_CACHE_LIFECYCLE', unit_only=True, observations=observations[0], bulk_controls=controls, full_layout_completed=False, page_accepted=False)
    except BaseException as error:
        run.evidence.update(status='FAILED', error=str(error))
        raise
    finally:
        run.save()
        print(run.path)

if __name__ == '__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute()
