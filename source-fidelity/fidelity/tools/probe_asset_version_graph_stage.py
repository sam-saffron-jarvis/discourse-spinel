#!/usr/bin/env python3
"""Actual full source-built asset-version graph/digest before MessageBus effects."""
import hashlib
import json
import os
import shutil
from probe_client_setup_prefix_stage import ClientSetupPrefixStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

GRAPH_FILES=('asset_version_graph_source.rb','original_asset_version_graph_source.rb','asset_version_graph_context.rb','asset_version_graph_original_context.rb')

class AssetVersionGraphStageRun(ClientSetupPrefixStageRun):
    success_status='PASS_SCOPED_ACTUAL_ASSET_VERSION_GRAPH_BEFORE_MESSAGE_BUS'
    expected_locale_boundary='original MessageBus last-message/publication lifecycle acquisition pending'
    expected_asset_version_bus_dispatched=False

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-asset-version-graph-stage',['bundle','exec','ruby',HERE/'tools/generate_asset_version_graph_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['asset_version_graph_source']=json.loads((self.path/'asset-version-graph-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in GRAPH_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        (self.path/'emitted/runtime/asset_version_graph.rbs').write_text('''module ActionView
  class SourceAssetLoadPath
    def assets: () -> Array[SourceAsset]
  end
end
module AssetVersionGraphBootstrap
  @load_path: ActionView::SourceAssetLoadPath?
  @root: String?
  @events: Array[String]?
  @graph: Array[Hash[Symbol, String]]?
  @digest: String?
  def self.bind: (ActionView::SourceAssetLoadPath path, String root, Array[String] events) -> nil
  def self.verified_load_path: () -> ActionView::SourceAssetLoadPath
  def self.assets: () -> Array[ActionView::SourceAsset]
  def self.graph: () -> Array[Hash[Symbol, String]]
  def self.note_digest: (String digest) -> nil
  def self.last_message: (String channel) -> CategoryCacheMessageBus::Message?
  def self.publish: (String channel, String value) -> Integer?
end
module RequestAssetVersionSource
  @assets_digest: String?
  def self.assets_digest: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "asset_version_graph_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'client_setup_prefix_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "asset_version_graph_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['asset_version_graph']
                assert item['asset_count']==len(item['assets']) and item['asset_count']>0 and item['message_bus_dispatched']==self.expected_asset_version_bus_dispatched
                expected=hashlib.md5('|'.join(sorted(asset['digested_path']for asset in item['assets'])).encode()).hexdigest()
                assert item['digest']==expected
                values.append(item)
        assert all(item==values[0]for item in values)
        self.env['FIDELITY_ASSET_VERSION_FAULT']='drop-member';controls={}
        try:
            for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-asset-version-drop-member';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'asset version digest does not cover full acquired graph'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_ASSET_VERSION_FAULT']
        self.evidence.update(actual_asset_version_graph=values[0],asset_version_graph_controls=controls,asset_version_message_bus_dispatched=self.expected_asset_version_bus_dispatched,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in GRAPH_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(AssetVersionGraphStageRun())
