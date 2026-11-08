#!/usr/bin/env python3
"""Exact two upcoming-default target getters in SVG settings_hash consumer."""
import json
import os
import shutil
from probe_svg_enum_stage import SvgEnumStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

DEFAULT_FILES=('svg_default_declarations.rb','svg_default_context.rb','svg_default_original_context.rb')

class SvgDefaultStageRun(SvgEnumStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_SETTINGS_UPCOMING_DEFAULT_TARGETS'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-default-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_default_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_default_source']=json.loads((self.path/'svg-default-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in DEFAULT_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        enum=self.path/'svg_enum_context.rb'
        text=enum.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_defaults(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_defaults(name, warn: true)\n')
        enum.write_text(text)
        original=self.path/'svg_top_menu_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_defaults(name)\n'))
        (self.path/'emitted/runtime/svg_defaults.rbs').write_text('''module SiteSettings
  class PortableReadStore
    def svg_change_enabled: (String name, String site, Hash[Symbol, Integer] statuses) -> bool
    def svg_default_value: (String name, String site, Hash[Symbol, Integer] statuses) -> untyped
  end
end
module SvgSettingsRead
  def self.additional_kind_without_defaults: (String name) -> String?
  def self.read_without_defaults: (String name, ?warn: bool) -> String
end
module SvgDefaultRead
  def self.read: (String name) -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_default_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_enum_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_default_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_defaults'];assert 'whispers_allowed_groups' in item
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('non-boolean-change','SVG default change is not Boolean'),('wrong-result','SVG upcoming default result changed')):
            self.env['FIDELITY_SVG_DEFAULT_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-default-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_DEFAULT_FAULT']
        self.evidence.update(actual_svg_defaults=values[0],svg_default_controls=controls,permission_maps_acquired=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in DEFAULT_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgDefaultStageRun())
