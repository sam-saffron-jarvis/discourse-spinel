#!/usr/bin/env python3
"""Source settings_hash consumer prefix with strict live scalar/upload getters."""
import json
import os
import shutil
from probe_svg_cache_stage import SvgCacheStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

SETTINGS_FILES=('svg_settings_declarations.rb','original_svg_settings_source.rb','svg_settings_context.rb','svg_settings_original_context.rb')

class SvgSettingsStageRun(SvgCacheStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_SETTINGS_HASH_GETTER_PREFIX'
    expected_locale_boundary='source getter '
    full_settings_snapshot_supported=False

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-settings-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_settings_stage.rb',app,self.path],cwd=ROOT/'discourse')
        self.evidence['svg_settings_source']=json.loads((self.path/'svg-settings-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in SETTINGS_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        (self.path/'emitted/runtime/svg_settings.rbs').write_text('''module SiteSettings
  class PortableReadStore
    def svg_definition: (String name) -> PortableDefinition?
    def svg_definitions: () -> Array[PortableDefinition]
    def svg_source_current: (String site) -> Hash[String, untyped]
    def svg_shadowed?: (String name, String site) -> bool
  end
end
module SvgSettingsRead
  @uploads: Hash[String, Upload]?
  @records: Hash[String, String]?
  @pending: String?
  def self.bind: () -> nil
  def self.definitions: () -> Array[SiteSettings::PortableDefinition]
  def self.names: () -> Array[String]
  def self.definition: (String name) -> SiteSettings::PortableDefinition
  def self.themeable?: (String name) -> bool
  def self.kind: (String name) -> String
  def self.pending: (String name) -> bot
  def self.upload: (String name) -> Upload?
  def self.read: (String name) -> String
  def self.record: (String name, String text) -> String
  def self.records: () -> Hash[String, String]
  def self.settings_hash: () -> bot
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_settings_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_cache_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_settings_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_settings']
                assert item['names']
                if self.full_settings_snapshot_supported:
                    assert item['pending_getter'] is None and item['full_snapshot_returned'] and not item['key_projection_only']
                else:
                    assert item['pending_getter'] not in item['names'] and not item['full_snapshot_returned']
                assert list(item['value_digests'])==item['names']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('drop-setting','SVG settings getter order changed'),('reverse-setting-order','SVG settings getter order changed'),('wrong-upload','SVG upload getter Stringification changed')):
            self.env['FIDELITY_SVG_SETTINGS_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-settings-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_SETTINGS_FAULT']
        self.evidence.update(actual_svg_settings_prefix=values[0],svg_settings_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in SETTINGS_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgSettingsStageRun())
