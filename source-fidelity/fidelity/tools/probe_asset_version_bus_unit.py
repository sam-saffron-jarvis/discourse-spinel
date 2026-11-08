#!/usr/bin/env python3
"""UNIT-only source MessageBus global lifecycle using the existing owned fixture."""
import json
import os
import shutil
from pathlib import Path
from probe_asset_version_bus_stage import AssetVersionBusStageRun
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

class AssetVersionBusUnitRun(AssetVersionBusStageRun):
    def generate(self):
        super().generate()
        shutil.copyfile(HERE/'test/asset_version_bus_unit.rb',self.path/'probe.rb')

def main():
    run=AssetVersionBusUnitRun()
    try:
        run.provenance();run.generate()
        run.command('native-compile',[ROOT/'spinel/spinel','--jobs=4','--int-overflow=promote','--rbs',run.path/'emitted','-I',Path.home()/'.cache/spin/packages/pg-0.2.0',run.path/'entry.rb','-o',run.path/'probe'])
        run.command('native',['strace','-f','-e','trace=execve,connect','-o',run.path/'native.trace',run.path/'probe'],timeout=120)
        compat=run.path/'compat';shutil.copytree(run.path/'emitted',compat/'emitted')
        for name in ('entry.rb','probe.rb'):shutil.copyfile(run.path/name,compat/name)
        shutil.copyfile(ROOT/'roundhouse/runtime/spinel/pg_driver_cruby.rb',compat/'emitted/runtime/pg_driver.rb')
        run.command('compat',['bundle','exec','ruby','--enable-frozen-string-literal',compat/'entry.rb'],timeout=120)
        run.command('generate-original-html-methods',['ruby',HERE/'tools/generate_html_stage_original_methods.rb',compat/'original_html_stage_methods.rb'])
        entry=compat/'entry-original.rb'
        entry.write_text((compat/'entry.rb').read_text().replace('require_relative "latest_html_stage_transport"','require_relative "latest_html_stage_transport"\nrequire_relative "original_html_stage_methods"'))
        run.command('compat-original',['bundle','exec','ruby','--enable-frozen-string-literal',entry],timeout=120)
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(run.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_ASSET_VERSION_BUS_UNIT ')]
            assert len(rows)==1 and rows[0]['publications']==1 and rows[0]['reads']==3
            values.append(rows[0]);lifecycle(run,name)
        assert values[0]==values[1]==values[2]
        controls={}
        for variable,fault,expected in (('FIDELITY_ASSET_BUS_FAULT','wrong-channel','category cache publication channel'),('FIDELITY_ASSET_BUS_FAULT','wrong-digest','asset-version publication digest'),('FIDELITY_CACHE_FAULT','shared-endpoint','protected/unknown cache endpoint'),('FIDELITY_CACHE_FAULT','wrong-runtime','category cache runtime ownership')):
            run.env[variable]=fault
            try:
                for runtime,argv in (('native',[run.path/'probe']),('compat',['bundle','exec','ruby',compat/'entry.rb'])):
                    name=runtime+'-asset-bus-unit-'+fault;code,_=run.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(run.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(run,name)
                    assert all(run.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del run.env[variable]
        run.evidence.update(status='PASS_UNIT_ORIGINAL_ASSET_VERSION_MESSAGE_BUS',unit_only=True,asset_version_bus=values[0],controls=controls,page_accepted=False)
    except BaseException as error:
        run.evidence.update(status='FAILED',error=str(error));raise
    finally:run.save();print(run.path)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);main()
