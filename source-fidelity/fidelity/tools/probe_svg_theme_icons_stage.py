#!/usr/bin/env python3
"""Actual source Theme settings/modifier SVG icon reads, no settings/rebake writes."""
import json
import os
import shutil
from pathlib import Path
from probe_svg_icon_producers_stage import SvgIconProducersStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

THEME_FILES=('svg_theme_icons_source.rb','original_svg_theme_icons_source.rb','svg_theme_icons_context.rb','svg_theme_icons_original_context.rb','svg_theme_icons_transport.rb')

class SvgThemeIconsStageRun(SvgIconProducersStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_THEME_ICONS'
    allow_svg_theme_cache=True
    expected_locale_boundary='actual SVG theme settings/modifier icons acquired; custom SVG/XML acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-theme-icons-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_theme_icons_stage.rb',app,self.path],cwd=ROOT/'discourse')
        proof=json.loads((self.path/'svg-theme-icons-source-proof.json').read_text());self.evidence['svg_theme_icons_source']=proof
        serving=Path(self.asset_provenance['root'])
        for relative,expected in proof['sources'].items():
            assert digest((serving/relative).read_bytes())==expected
            self.asset_provenance['files'][relative]=expected
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in THEME_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        array=self.path/'theme_array_transport.rb'
        text=array.read_text().replace('  def admitted_value?(data)\n','  def admitted_value?(data)\n    return admitted_svg_theme_value?(data) if data["hash_key"] == theme_cache_key && (svg_theme_settings_key?(data["key"]) || svg_theme_modifier_key?(data["key"]))\n')
        array.write_text(text)
        transport=self.path/'category_cache_transport.rb'
        text=transport.read_text().replace('key == "compiler_version" ||','svg_theme_settings_key?(key) || svg_theme_modifier_key?(key) || key == "compiler_version" ||')
        transport.write_text(text)
        context=self.path/'category_cache_context.rb'
        text=context.read_text().replace('hit = lease.theme_field_key?(key) ?', 'hit = lease.svg_theme_settings_key?(key) ? acquired_theme_compiler_cache.svg_theme_settings_hit(key) : lease.svg_theme_modifier_key?(key) ? acquired_theme_compiler_cache.defer_get_set_svg_theme_modifier(key) { raise "genuine SVG modifier hit recomputed" } : lease.theme_field_key?(key) ?')
        context.write_text(text)
        source=self.path/'svg_icon_producers_source.rb'
        stop="raise HtmlRenderingBoundary, 'actual SVG settings/plugin/badge/group icons acquired; theme icon acquisition pending'"
        text=source.read_text();assert text.count(stop)==1
        source.write_text(text.replace(stop,".merge(theme_icons(theme_id))\n        raise HtmlRenderingBoundary, 'actual SVG theme settings/modifier icons acquired; custom SVG/XML acquisition pending'"))
        (self.path/'emitted/runtime/svg_theme_icons.rbs').write_text('''class CategoryCacheLease
  def svg_theme_settings_key?: (String key) -> bool
  def svg_theme_modifier_key?: (String key) -> bool
  def note_svg_theme_value: (String key, untyped value) -> nil
  def admitted_svg_theme_value?: (Hash[String, untyped] data) -> bool
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_svg_theme_settings: (String key) { () -> Hash[String, untyped] } -> Hash[String, untyped]
    def defer_get_set_svg_theme_modifier: (String key) { () -> Array[String] } -> Array[String]
    def svg_theme_settings_hit: (String key) -> Hash[String, untyped]
  end
end
class SvgThemeSettingsRead
  @theme_id: Integer
  @settings_field: ThemeField?
  @settings_field_loaded: bool
  def initialize: (Theme theme) -> void
  def id: () -> Integer
  def settings_field: () -> ThemeField?
end
module SvgThemeSettingsMethods
  def cached_settings: () -> Hash[String, untyped]
  def settings: () -> Hash[String, untyped]
  def build_settings_hash: () -> Hash[String, untyped]
end
module SvgThemeIcons
  def self.cache: () -> CategoryCacheApplication::DistributedCache
  def self.cache_settings: (String key) { () -> Hash[String, untyped] } -> Hash[String, untyped]
  def self.cache_modifier: (String key) { () -> Array[String] } -> Array[String]
  def self.lookup_modifier: (Array[Integer] ids, Symbol name) -> Array[String]
  def self.source_theme_icons: (Integer id) -> Array[String]
  def self.settings_field_reads: () -> Integer
  def self.settings_field_present: () -> bool?
  def self.settings_key: (Integer id) -> String
  def self.modifier_key: (Array[Integer] ids) -> String
end
module RequestSvgSource
  def self.theme_icons: (Integer? id) -> Array[String]
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_theme_icons_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_icon_producers_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_theme_icons_original_context"\n')

    def compat_diagnostic(self):
        super().compat_diagnostic()
        controls={}
        for fault,expected in (('settings-type','nonempty Theme settings Hash profile unacquired'),('nonempty-settings','nonempty Theme settings Hash profile unacquired'),('modifier-type','Theme SVG modifier result must be String Array')):
            self.env['FIDELITY_SVG_THEME_FAULT']=fault
            try:
                name='compat-preflight-svg-theme-'+fault
                code,_=self.command(name,['bundle','exec','ruby',self.path/'compat-preflight/entry.rb'],check=False,timeout=120)
                assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_THEME_FAULT']
        self.evidence['svg_theme_focused_preflight_controls']=controls

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[row['template_prefix']['svg_theme_icons']for row in rows]
            assert len(items)==2 and items[0]==items[1]
            assert not items[0]['warm_republished'] and items[0]['settings_field_reads']>0
            values.append(items[0])
        assert all(value==values[0]for value in values)
        controls={}
        for fault,expected in (('settings-type','nonempty Theme settings Hash profile unacquired'),('nonempty-settings','nonempty Theme settings Hash profile unacquired'),('modifier-type','Theme SVG modifier result must be String Array')):
            self.env['FIDELITY_SVG_THEME_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-theme-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_THEME_FAULT']
        self.evidence.update(actual_svg_theme_icons=values[0],svg_theme_icons_controls=controls,svg_theme_icons_acquired=True,full_settings_hash_acquired=True,svg_xml_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in THEME_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgThemeIconsStageRun())
