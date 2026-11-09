#!/usr/bin/env python3
"""Actual source client setup/meta consumer; environment object API is not native."""
import json
import os
import shutil
from pathlib import Path
from probe_svg_bundle_stage import SvgBundleStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

META_FILES=('client_meta_declarations.rb','client_meta_source.rb','client_meta_storage_source.rb','client_meta_bus_source.rb','original_client_meta_palette.rb','original_client_meta_layout.rb','client_meta_context.rb','client_meta_original_context.rb')

class ClientMetaStageRun(SvgBundleStageRun):
    success_status='PASS_SCOPED_ACTUAL_CLIENT_SETUP_META_CONSUMER_O0'
    client_meta_supported=True
    expected_locale_boundary='actual client setup meta consumer returned; remaining layout acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-client-meta-stage',['bundle','exec','ruby',HERE/'tools/generate_client_meta_stage.rb',self.path],cwd=ROOT/'discourse')
        proof=json.loads((self.path/'client-meta-source-proof.json').read_text());self.evidence['client_meta_source']=proof
        serving=Path(self.asset_provenance['root'])
        for relative,expected in proof['sources'].items():
            assert digest((serving/relative).read_bytes())==expected
            self.asset_provenance['files'][relative]=expected
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in META_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        context=self.path/'client_highlight_context.rb'
        text=context.read_text();assert text.count('  def client_side_setup_data\n')==1
        context.write_text(text.replace('  def client_side_setup_data\n','  def client_setup_without_meta_completion\n'))
        bundle=self.path/'svg_bundle_context.rb'
        text=bundle.read_text()
        stop="    raise HtmlRenderingBoundary, 'actual SVG XML bundle/version/path acquired; client setup/meta serialization pending'"
        assert text.count(stop)==1
        text=text.replace(stop,'''    # TEST scheduling fence only after complete actual cold source path return:
    # wait for genuine owned deferred publication before the next source
    # development all_icons consumer. No cache seed/preload/value is supplied.
    cache = CategoryCacheBootstrap.svg_cache
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    until cache.svg_values.key?(key)
      raise 'client meta SVG publication fence missing' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    @path''')
        # Source full development setup invokes all_icons AFTER actual path.
        text=text.replace("'group_icons:miss', 'settings_icons:hit'", "'group_icons:miss', \"icons_#{id_key}:hit\", 'settings_icons:hit'")
        text=text.replace('warm = ["version_#{id_key}:hit", \'settings_icons:hit\'', 'warm = ["version_#{id_key}:hit", "icons_#{id_key}:hit", \'settings_icons:hit\'')
        bundle.write_text(text)
        transport=self.path/'category_cache_transport.rb'
        text=transport.read_text().replace('  def authorize(command)\n','  def authorize(command)\n    return authorize_client_meta_read(command) if client_meta_read_command?(command)\n')
        transport.write_text(text)
        signature=self.path/'emitted/runtime/client_setup_prefix.rbs'
        signature.write_text(signature.read_text().replace('def meta: (id: String, data: Hash[Symbol, untyped]) -> bot','def meta: (id: String, data: Hash[Symbol, untyped]) -> ActionView::HtmlFragment'))
        signature=self.path/'emitted/runtime/svg_bundle.rbs'
        signature.write_text(signature.read_text().replace('def self.acquire_path: (Integer id) -> bot','def self.acquire_path: (Integer id) -> String'))
        (self.path/'emitted/runtime/client_meta.rbs').write_text('''module ClientMetaRead
  def self.error_reporting: () -> bool?
  def self.all_icons: (Integer id) -> Array[String?]
  def self.last_id: (String channel) -> Integer
  def self.serialize_meta: (String id, Hash[Symbol, untyped] data) -> String
end
module ClientMetaSource
  def source_client_side_setup_data: () -> Hash[Symbol, untyped]
end
module ClientMetaUploadRead
  def self.enable_s3_uploads: () -> bool
end
module ClientMetaGlobalStorage
  @use_s3: Symbol?
  def self.use_s3?: () -> bool
end
module CategoryCacheMessageBus::Implementation
  def last_id: (String channel, ?String? site) -> Integer
end
class CategoryCacheLease
  def client_meta_read_command?: (Array[String | Integer] command) -> bool
  def authorize_client_meta_read: (Array[String | Integer] command) -> bool
  def client_meta_file_reads: () -> Integer
end
class ActionController::CookieJar
  def client_meta_nullable_read: (Symbol key) -> String?
end
class ClientMetaCookieView
  def initialize: (ActionController::CookieJar jar) -> void
  def []: (Symbol key) -> String?
end
class ListBodyContext
  @client_meta_cookies: ClientMetaCookieView?
  @client_meta_data: Hash[Symbol, untyped]?
  def client_setup_without_meta_completion: () -> Hash[Symbol, untyped]
  def user_scheme_id: () -> Integer?
  def user_dark_scheme_id: () -> Integer?
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "client_meta_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_bundle_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "client_meta_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[row['template_prefix']['client_meta']for row in rows]
            assert len(items)==2 and items[0]==items[1]
            assert items[0]['file_change_read'] and items[0]['nullable_staff_preserved'] and not items[0]['generic_setup_hash_api_supported']
            assert items[0]['html'].startswith('<meta id="data-discourse-setup"') and items[0]['bytes']>0
            values.append(items[0])
        assert all(value==values[0]for value in values)
        controls={}
        for fault,expected in self.meta_faults():
            self.env['FIDELITY_CLIENT_META_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-client-meta-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_CLIENT_META_FAULT']
        self.evidence.update(actual_client_setup_meta=values[0],client_meta_controls=controls,client_setup_meta_acquired=True,generic_client_setup_hash_api_supported=False,full_layout_completed=False)

    def meta_faults(self):
        return (('unescaped-json','client setup meta escaping/output changed'),('wrong-attribute','client setup meta escaping/output changed'),('wrong-user-scheme','client setup default user palette differs'),('wrong-file-channel','client meta file-change source channel'))

    def compat_diagnostic(self):
        super().compat_diagnostic()
        controls={}
        for fault,expected in self.meta_faults():
            self.env['FIDELITY_CLIENT_META_FAULT']=fault
            try:
                name='compat-preflight-client-meta-'+fault
                code,_=self.command(name,['bundle','exec','ruby',self.path/'compat-preflight/entry.rb'],check=False,timeout=120)
                assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_CLIENT_META_FAULT']
        self.evidence['client_meta_focused_preflight_controls']=controls

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in META_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(ClientMetaStageRun())
