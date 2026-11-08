#!/usr/bin/env python3
"""Original conditional global asset-version lifecycle on existing owned fixture."""
import json
import os
import shutil
from probe_asset_version_graph_stage import AssetVersionGraphStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

BUS_FILES=('asset_version_bus_source.rb','asset_version_bus_transport.rb','asset_version_bus_context.rb','asset_version_bus_original_context.rb')

class AssetVersionBusStageRun(AssetVersionGraphStageRun):
    success_status='PASS_SCOPED_ACTUAL_ASSET_VERSION_MESSAGE_BUS_LIFECYCLE'
    expected_locale_boundary='client setup remaining inputs acquisition pending'
    expected_asset_version_bus_dispatched=True
    setup_asset_version_returned=True

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-asset-version-bus-stage',['bundle','exec','ruby',HERE/'tools/generate_asset_version_bus_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['asset_version_bus_source']=json.loads((self.path/'asset-version-bus-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in BUS_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        transport=self.path/'category_cache_transport.rb'
        text=transport.read_text()
        anchor='    name = command[0].to_s.upcase\n    case name'
        assert text.count(anchor)==1
        text=text.replace(anchor,'    return authorize_asset_version(command) if asset_version_command?(command)\n'+anchor)
        text=text.replace('    CategoryCacheOutput.synchronize { @policy.observe(command, response) }','    observe_asset_version(command, response)\n    CategoryCacheOutput.synchronize { @policy.observe(command, response) }')
        anchor='    message = CategoryCacheMessageBus::Message.decode(row[2])'
        assert text.count(anchor)==1
        text=text.replace(anchor,anchor+'\n    return validate_asset_version_payload(JSON.parse(message.data)) if message.channel == asset_version_channel')
        transport.write_text(text)
        graph=self.path/'asset_version_graph_context.rb'
        text=graph.read_text().replace('    @graph = []','    @graph ||= []').replace('    @digest = nil','    # Keep prior acquired observation metadata across genuine source memo hits.')
        text=text.replace("    events << 'asset_version_graph_acquisition'", "    @computations = (@computations || 0) + 1\n    events << 'asset_version_graph_acquisition'")
        text=text.replace('    @digest = value','    CategoryCacheBootstrap.lease.note_asset_version(value)\n    @digest = value')
        text=text.replace('message_bus_dispatched: false','message_bus_dispatched: CategoryCacheBootstrap.lease.asset_version_reads > 0')
        graph.write_text(text)
        setup=self.path/'client_setup_prefix_source.rb'
        text=setup.read_text();assert "raise 'client setup asset-version boundary unexpectedly returned'" in text
        setup.write_text(text.replace("raise 'client setup asset-version boundary unexpectedly returned'", "loading_admin?\nraise 'client setup loading-admin boundary unexpectedly returned'"))
        (self.path/'emitted/runtime/asset_version_bus.rbs').write_text('''class CategoryCacheLease
  @asset_version_digest: String?
  @asset_version_publications: Integer?
  @asset_version_reads: Integer?
  def note_asset_version: (String value) -> nil
  def asset_version_publications: () -> Integer
  def asset_version_reads: () -> Integer
end
module AssetVersionGraphBootstrap
  @computations: Integer?
  @returned: Integer?
  def self.computations: () -> Integer
  def self.returned: () -> Integer
  def self.note_returned: () -> nil
end
module ClientSetupReadBootstrap
  def self.source_assets_digest: () -> String
  def self.asset_version_memoized?: () -> bool
  def self.reset_unit_asset_memo!: () -> nil
end
module RequestAssetVersionSource
  def self.memoized?: () -> bool
  def self.reset_unit_memo!: () -> nil
end
class ListBodyContext
  @asset_version_was_memoized: bool?
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "asset_version_bus_transport"\nrequire_relative "asset_version_bus_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'asset_version_graph_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "asset_version_bus_original_context"\n')

    def bus_observations(self,name):
        rows=[json.loads(line.split(' ',1)[1]) for line in (self.path/(name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
        values=[row['template_prefix']['asset_version_bus'] for row in rows]
        assert len(values)==2 and all(v['publications']==1 and v['source_memo_warm_identity'] and v['message_id']==1 for v in values), (name, values)
        assert values[0]['was_memoized'] is False
        return values

    def verify_continuation(self):
        super().verify_continuation()
        values=[self.bus_observations(name) for name in ('native','compat','compat-original')]
        assert values[0]==values[1]==values[2]
        assert [v['was_memoized'] for v in values[0]]==[False,True]
        assert [v['computations'] for v in values[0]]==[1,1]
        assert [v['source_reads_before_audit'] for v in values[0]]==[1,2]
        controls={}; reset_values=[]
        self.env['FIDELITY_ASSET_BUS_UNIT_RESET']='1'
        try:
            for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-asset-version-unit-memo-reset'
                self.command(name,argv,timeout=120)
                rows=self.bus_observations(name)
                assert [v['was_memoized'] for v in rows]==[False,False] and [v['computations'] for v in rows]==[1,2]
                assert [v['source_reads_before_audit'] for v in rows]==[1,3]
                reset_values.append(rows)
                lifecycle(self,name)
            for fault,expected in (('missing-publication','asset-version publication missing'),('redundant-publication','asset-version redundant publication'),('wrong-channel','category cache publication channel'),('wrong-digest','asset-version publication digest')):
                self.env['FIDELITY_ASSET_BUS_FAULT']=fault
                try:
                    for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                        name=runtime+'-asset-version-'+fault
                        code,_=self.command(name,argv,check=False,timeout=120)
                        assert code!=0 and expected in (self.path/(name+'.stderr')).read_text(), (name,code)
                        lifecycle(self,name)
                        assert all(self.evidence[key][name] for key in ('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                        controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
                finally:del self.env['FIDELITY_ASSET_BUS_FAULT']
        finally:del self.env['FIDELITY_ASSET_BUS_UNIT_RESET']
        assert reset_values[0]==reset_values[1]
        self.evidence.update(actual_asset_version_bus=values[0],asset_version_bus_unit_reset=reset_values[0],asset_version_bus_controls=controls,asset_version_message_bus_dispatched=True,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in BUS_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(AssetVersionBusStageRun())
