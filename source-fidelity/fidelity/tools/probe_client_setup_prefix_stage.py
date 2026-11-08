#!/usr/bin/env python3
"""Actual source tag-builder ownership and client setup read prefix, not full setup."""
import json
import os
import shutil
from probe_markdown_link_stage import MarkdownLinkStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

SETUP_FILES=('client_setup_builder_source.rb','client_setup_prefix_source.rb','original_client_setup_source.rb','client_setup_prefix_context.rb','client_setup_prefix_original_context.rb')

class ClientSetupPrefixStageRun(MarkdownLinkStageRun):
    success_status='PASS_SCOPED_ACTUAL_CLIENT_SETUP_PREFIX_BEFORE_ASSET_VERSION'
    expected_locale_boundary='asset-version graph/MessageBus lifecycle acquisition pending'
    setup_asset_version_returned=False

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-client-setup-prefix-stage',['bundle','exec','ruby',HERE/'tools/generate_client_setup_prefix_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['client_setup_prefix_source']=json.loads((self.path/'client-setup-prefix-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in SETUP_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        source=self.path/'client_setup_builder_source.rb'
        text=source.read_text().replace('@tag_builder ||= ClientSetupTagBuilder.new(self)', '@tag_builder = nil if ENV.fetch("FIDELITY_SETUP_BUILDER_FAULT", "") == "fresh-builder"\n    @tag_builder ||= ClientSetupTagBuilder.new(self)')
        source.write_text(text)
        (self.path/'emitted/runtime/client_setup_prefix.rbs').write_text('''class ClientSetupTagBuilder
  @view_context: ListBodyContext
  def initialize: (ListBodyContext view_context) -> void
  def owned_by?: (ListBodyContext view) -> bool
  def meta: (id: String, data: Hash[Symbol, untyped]) -> bot
end
class ListBodyContext
  @tag_builder: ClientSetupTagBuilder?
end
module ClientSetupBuilderSource
  def source_setup_tag_builder: () -> ClientSetupTagBuilder
end
module ClientSetupReadBootstrap
  @inputs: Hash[Symbol, String?]?
  @events: Array[String]?
  def self.inputs: () -> Hash[Symbol, String?]
  def self.record_input: (Symbol name, String? value) -> String?
  def self.begin_request: (Array[String] events) -> nil
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "client_setup_prefix_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'markdown_link_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "client_setup_prefix_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['client_setup_prefix']
                assert item['builder_owned'] and item['builder_warm_identity']
                assert list(item['inputs'])==self.evidence['client_setup_prefix_source']['prefix_keys'][:None if self.setup_asset_version_returned else -1]
                values.append(item)
        assert all(item==values[0]for item in values)
        self.env['FIDELITY_SETUP_BUILDER_FAULT']='fresh-builder';controls={}
        try:
            for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-setup-fresh-builder';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'client setup tag builder warm identity changed'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_SETUP_BUILDER_FAULT']
        self.evidence.update(actual_client_setup_prefix=values[0],client_setup_prefix_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in SETUP_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(ClientSetupPrefixStageRun())
