#!/usr/bin/env python3
"""Actual source complete SVG XML bundle/version/path, not client-meta or HTML200."""
import json
import os
import shutil
from pathlib import Path
from probe_svg_theme_icons_stage import SvgThemeIconsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

BUNDLE_FILES=('svg_bundle_declarations.rb','svg_bundle_bulk_source.rb','svg_bundle_transport.rb','svg_bundle_source.rb','original_svg_bundle_source.rb','svg_bundle_context.rb','svg_bundle_original_context.rb','svg_xml_backend.rb','svg_sprite_read_component.rb')

class SvgBundleStageRun(SvgThemeIconsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_XML_BUNDLE_VERSION_PATH'
    svg_bundle_supported=True
    expected_locale_boundary='actual SVG XML bundle/version/path acquired; client setup/meta serialization pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        script='''require "pg"; require "json"
c=PG.connect(ENV.fetch("DATABASE_URL"))
begin
  raise "writable SVG read catalog" unless c.exec("SHOW default_transaction_read_only").getvalue(0,0)=="on"
  puts JSON.generate(c.exec("SELECT column_name,data_type,udt_name,is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='theme_svg_sprites' ORDER BY ordinal_position").to_a)
ensure
  c.close
end
'''
        _,output=self.command('svg-sprite-read-catalog',['bundle','exec','ruby','-e',script],cwd=ROOT/'discourse')
        rows=json.loads(output)
        selected={row['column_name']:row['data_type']for row in rows if row['column_name']in{'theme_id','upload_id','sprite'}}
        assert selected=={'theme_id':'integer','upload_id':'integer','sprite':'bytea'},selected
        self.evidence['svg_sprite_pluck_only_source']={'catalog':rows,'columns':list(selected),'full_model_or_binary_codec_acquired':False,'nonempty_row_decode':'explicit refusal before value use','data_sql':'original shared ORM Relation where/pluck, never hand-written SQL'}
        self.command('generate-svg-bundle-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_bundle_stage.rb',app,self.path],cwd=ROOT/'discourse')
        proof=json.loads((self.path/'svg-bundle-source-proof.json').read_text());self.evidence['svg_bundle_source']=proof
        candidates=sorted((HERE/'build').glob('native-svg-xml-*/evidence.json'),key=lambda p:p.stat().st_mtime,reverse=True)
        engine=None
        for file in candidates:
            item=json.loads(file.read_text());library=item.get('native_library',{})
            if item.get('status')=='PASS_SCOPED_RUBY_FREE_SVG_XML_SYMBOLS_COMPONENT' and item.get('adapter_sha256')==digest((HERE/'test/svg_xml_backend.rb').read_bytes()) and item.get('native_source_sha256')==digest((HERE/'test/svg_xml_native.cc').read_bytes()) and library and Path(library['path']).exists() and digest(Path(library['path']).read_bytes())==library['sha256']:
                engine=item;break
        assert engine is not None,'matching executed source XML component unavailable'
        self.xml_engine=engine
        self.env.update(FIDELITY_SVG_XML_LIBRARY=engine['native_library']['path'],FIDELITY_SVG_XML_LIBRARY_SHA256=engine['native_library']['sha256'])
        self.evidence['svg_xml_engine']=engine
        serving=Path(self.asset_provenance['root'])
        for relative,expected in {**proof['sources'],**engine['source_inputs']['files']}.items():
            assert digest((serving/relative).read_bytes())==expected
            self.asset_provenance['files'][relative]=expected
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in BUNDLE_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        transport=self.path/'svg_cache_transport.rb'
        text=transport.read_text().replace("key.is_a?(String) && (['badge_icons'", "key.is_a?(String) && (svg_sprite_nil_key?(key) || ['badge_icons'")
        text=text.replace("  def admitted_svg_value?(data)\n", "  def admitted_svg_value?(data)\n    return admitted_svg_bundle_value?(data) if svg_sprite_nil_key?(data['key']) || data['key'].to_s.start_with?('version_')\n")
        transport.write_text(text)
        transport=self.path/'category_cache_transport.rb'
        text=transport.read_text().replace('"svg_sprite_set"]','"svg_sprite_set", "svg_sprite_bulk_set"]')
        text=text.replace('(data["value"].is_a?(String) || admitted_field_value?(data))','(data["value"].is_a?(String) || admitted_field_value?(data) || admitted_svg_bundle_value?(data))')
        transport.write_text(text)
        context=self.path/'category_cache_context.rb'
        text=context.read_text().replace('record[:queued] - lease.field_bulk_jobs + lease.field_bulk_members','record[:queued] - lease.field_bulk_jobs + lease.field_bulk_members - lease.svg_bulk_jobs + lease.svg_bulk_members')
        text=text.replace('record[:field_bulk_jobs] = lease.field_bulk_jobs','record[:svg_bulk_jobs] = lease.svg_bulk_jobs\n        record[:svg_bulk_members] = lease.svg_bulk_members\n        record[:field_bulk_jobs] = lease.field_bulk_jobs')
        context.write_text(text)
        (self.path/'emitted/runtime/svg_bundle.rbs').write_text('''class CategoryCacheLease
  def svg_sprite_nil_key?: (String key) -> bool
  def note_svg_sprite_value: (String key, Hash[String, String]? value) -> nil
  def note_svg_version: (String key, String value) -> nil
  def admitted_svg_bundle_value?: (Hash[String, untyped] data) -> bool
  def note_svg_bulk_enqueue: (Integer count) -> nil
  def svg_bulk_jobs: () -> Integer
  def svg_bulk_members: () -> Integer
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_theme_sprites: (Array[Integer] keys, ^(Integer) -> String key_block) { (Array[Integer]) -> Array[Hash[String, String]?] } -> Hash[Integer, Hash[String, String]?]
  end
end
module RequestSvgSource
  @core_svgs: Hash[String, String]?
  @svg_files: Array[String]?
  @plugin_svgs: Hash[String, String]?
  def self.symbols_for: (String filename, String source, strict: bool) -> Hash[String, String]
  def self.core_svgs_files: () -> Array[String]
  def self.core_svgs: () -> Hash[String, String]
  def self.plugin_svgs: () -> Hash[String, String]
  def self.custom_svgs: (Integer? id) -> Hash[String, String]
  def self.theme_svgs: (Integer? id) -> Hash[String, String]
  def self.custom_icons: (Integer? id) -> Array[String]
end
module SvgBundleBootstrap
  @backend: SvgXmlSymbolsBackend?
  @files: Hash[String, String]?
  @theme_queries: Integer?
  @path: String?
  @version_hit_on_entry: bool?
  def self.backend: () -> SvgXmlSymbolsBackend
  def self.read_svg: (String path) -> String
  def self.files: () -> Hash[String, String]
  def self.symbols_for: (String filename, String source, strict: bool) -> Hash[String, String]
  def self.note_theme_query: () -> nil
  def self.theme_queries: () -> Integer
  def self.path: () -> String?
  def self.version_hit_on_entry: () -> bool?
  def self.source_path: (Integer id) -> String
  def self.source_bundle: (Integer id) -> String
  def self.source_version: (Integer id) -> String
  def self.source_icons: (Integer id) -> Array[String?]
  def self.source_core: () -> Hash[String, String]
  def self.source_custom: (Integer id) -> Hash[String, String]
  def self.acquire_path: (Integer id) -> bot
end
class SvgXmlSymbolsBackend
  def initialize: (String path) -> void
  def symbols_for: (String filename, String source, strict: bool) -> Hash[String, String]
  def active_documents: () -> Integer
  def calls: () -> Integer
  def version: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_bundle_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_theme_icons_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_bundle_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[row['template_prefix']['svg_bundle']for row in rows]
            assert len(items)==2 and items[0]==items[1] and items[0]['source_path_returned']
            assert items[0]['core_symbol_count']>0 and items[0]['bundle_bytes']>0 and not items[0]['warm_nil_sprite_recomputed']
            stats=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_SVG_XML_LIFECYCLE ')]
            assert len(stats)==2 and all(value['active_documents']==0 for value in stats)
            if name!='compat-original':assert stats[0]['calls']==stats[1]['calls']==len(self.xml_engine['source_inputs']['files'])
            self.evidence.setdefault('svg_xml_runtime_lifecycle',{})[name]=stats
            values.append(items[0])
        assert all(value==values[0]for value in values)
        controls={}
        for fault,expected in self.bundle_faults():
            self.env['FIDELITY_SVG_BUNDLE_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-bundle-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_BUNDLE_FAULT']
        self.evidence.update(actual_svg_bundle=values[0],svg_bundle_controls=controls,svg_xml_acquired=True,svg_path_acquired=True,full_settings_hash_acquired=True,client_setup_meta_acquired=False,full_layout_completed=False)

    def bundle_faults(self):
        return (('wrong-library','SVG XML library provenance changed'),('wrong-symbol','SVG XML engine result changed'),('wrong-version','SVG version result type changed'),('drop-core-icon','SVG source default icon missing'),('nil-as-miss','SVG warm nil sprite cache recomputed'),('nonempty-sprite','nonempty Theme SVG sprite profile unacquired'))

    def compat_diagnostic(self):
        super().compat_diagnostic()
        controls={}
        for fault,expected in self.bundle_faults():
            self.env['FIDELITY_SVG_BUNDLE_FAULT']=fault
            try:
                name='compat-preflight-svg-bundle-'+fault
                code,_=self.command(name,['bundle','exec','ruby',self.path/'compat-preflight/entry.rb'],check=False,timeout=120)
                assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_BUNDLE_FAULT']
        self.evidence['svg_bundle_focused_preflight_controls']=controls

    def command(self,name,argv,**kwargs):
        if name=='native-compile':
            argv=list(argv)
            argv[1:1]=['-O','0']
            self.evidence['native_compilation_profile']={'optimization':'O0','monolithic_timeout_seconds':600,'reason':'bounded actual execution after retained O2 frontend+CC timeout; no behavior/source/cleanup assertions waived','O2_profile_accepted':False}
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in BUNDLE_FILES:shutil.copyfile(self.path/item,tree/item)
            prior=self.env.get('RUBYLIB')
            paths=[]
            for path,expected in self.xml_engine['fiddle']['files'].items():
                assert digest(Path(path).read_bytes())==expected
                if str(Path(path).parent)not in paths:paths.append(str(Path(path).parent))
            self.env['RUBYLIB']=os.pathsep.join(paths+([prior]if prior else[]))
            try:return super().command(name,argv,**kwargs)
            finally:
                if prior is None:self.env.pop('RUBYLIB',None)
                else:self.env['RUBYLIB']=prior
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgBundleStageRun())
