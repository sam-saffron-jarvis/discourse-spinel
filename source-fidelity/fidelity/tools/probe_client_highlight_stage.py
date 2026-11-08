#!/usr/bin/env python3
"""Actual owned-controller loading_admin? and readonly HighlightJs acquisition."""
import hashlib
import json
import os
import shutil
from pathlib import Path
from probe_asset_version_bus_stage import AssetVersionBusStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

HIGHLIGHT_FILES=('original_client_loading_admin_source.rb','client_highlight_setup_source.rb','client_loading_admin_source.rb','client_highlight_source.rb','original_client_highlight_source.rb','client_highlight_context.rb','client_highlight_original_context.rb')

class ClientHighlightStageRun(AssetVersionBusStageRun):
    success_status='PASS_SCOPED_ACTUAL_LOADING_ADMIN_HIGHLIGHT_JS_BEFORE_SVG'
    expected_locale_boundary='SVG sprite acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-client-highlight-stage',['bundle','exec','ruby',HERE/'tools/generate_client_highlight_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['client_highlight_source']=json.loads((self.path/'client-highlight-source-proof.json').read_text())
        serving=Path(self.asset_provenance['root']);original=ROOT/'discourse'
        relative=Path('vendor/runtime_node_modules/highlightjs/languages')
        package=Path('frontend/discourse/node_modules/@highlightjs/cdn-assets')
        manifest=json.loads((serving/package/'package.json').read_text())
        assert manifest['name']=='@highlightjs/cdn-assets' and manifest['version']=='11.12.0'
        lock=(original/'pnpm-lock.yaml').read_text()
        assert "'@highlightjs/cdn-assets@11.12.0':" in lock
        names=sorted(p.name for p in(serving/relative).glob('*')if p.is_file())
        assert names and names==sorted(p.name for p in(original/relative).glob('*')if p.is_file())
        for name in names:
            path=serving/relative/name
            assert path.resolve().is_relative_to(serving.resolve())
            data=path.read_bytes()
            assert data==(original/relative/name).read_bytes()==(serving/package/'languages'/name).read_bytes()==(original/package/'languages'/name).read_bytes(),name
            self.asset_provenance['files'][str(relative/name)]=digest(data)
        self.evidence['highlight_vendor_acquisition']={'package':manifest['name'],'version':manifest['version'],'files':len(names),'original_serving_and_installed_package_bytes_equal':True,'archive_integrity_reverified':False}
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in HIGHLIGHT_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        shutil.copyfile(self.path/'client_highlight_setup_source.rb',self.path/'client_setup_prefix_source.rb')
        source=self.path/'client_highlight_source.rb'
        text=source.read_text().replace('@lang_string_cache ||= {}', '@lang_string_cache = nil if ENV.fetch("FIDELITY_CLIENT_PATH_FAULT", "") == "discard-highlight-cache"\n    @lang_string_cache ||= {}')
        text=text.replace('langs.filter_map do |lang|', '(ENV.fetch("FIDELITY_CLIENT_PATH_FAULT", "") == "drop-language" ? langs.drop(1) : langs).filter_map do |lang|')
        source.write_text(text)
        bus=self.path/'asset_version_bus_context.rb'
        text=bus.read_text().replace('  def client_side_setup_data\n','  def asset_version_client_side_setup_data\n').replace('  def expected_body_events\n','  def expected_asset_version_bus_events\n')
        bus.write_text(text)
        (self.path/'emitted/runtime/client_highlight.rbs').write_text('''module RequestHighlightJs
  @languages_dir: String?
  @lang_string_cache: Hash[String, Hash[Symbol, String]]?
  def self.languages_dir: () -> String
  def self.cache: () -> Hash[String, Hash[Symbol, String]]
  def self.bundle: (Array[String] langs) -> String
  def self.version: (String languages) -> String
  def self.path: () -> String
end
module ClientHighlightBootstrap
  @root: String?
  @events: Array[String]?
  @files: Hash[String, String]?
  @reads: Integer?
  @path: String?
  @admin_value: bool?
  def self.bind: (String root, Array[String] events) -> nil
  def self.vendored_path: (String relative) -> String
  def self.read_language: (String path) -> String
  def self.asset_url_salt: () -> String?
  def self.files: () -> Hash[String, String]
  def self.reads: () -> Integer
  def self.source_path: () -> String
  def self.source_version: (String languages) -> String
  def self.source_cache: () -> Hash[String, Hash[Symbol, String]]
  def self.record_admin: (bool value) -> bool
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "client_highlight_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'asset_version_bus_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "client_highlight_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[];root=Path(self.asset_provenance['root'])
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['client_highlight']
                assert item['disable_custom_css'] is False and item['controller_class']=='HtmlStageObservedController' and item['warm_digest_identity']
                files=[]
                for lang in item['languages'].split('|'):
                    file=root/'vendor/runtime_node_modules/highlightjs/languages'/(lang+'.min.js')
                    if file.exists():
                        data=file.read_bytes();files.append(data.decode())
                        assert item['files'][file.name]==digest(data)
                js='export default function registerLanguages(hljs) {\n  '+'\n'.join(files)+'\n}\n'
                version=self.evidence['client_highlight_source']['highlight_version']
                expected=hashlib.sha1((js+f'|{version}|'+(item['salt']or'')).encode()).hexdigest()
                assert item['version']==expected and item['path'].endswith('/'+expected+'.js')
                assert item['reads']==len(files)>0
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-admin','loading_admin? differs from genuine controller owner'),('wrong-highlight-path','wrong acquired HighlightJs path'),('discard-highlight-cache','HighlightJs source cache missing'),('drop-language','HighlightJs language coverage missing')):
            self.env['FIDELITY_CLIENT_PATH_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-client-highlight-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_CLIENT_PATH_FAULT']
        self.evidence.update(actual_client_highlight=values[0],client_highlight_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in HIGHLIGHT_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(ClientHighlightStageRun())
