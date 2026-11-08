#!/usr/bin/env python3
"""Source experimental core upcoming getter reads, not activation/default migrations."""
import json
import os
import shutil
from probe_svg_preference_enums_stage import SvgPreferenceEnumsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

EXPERIMENTAL_FILES=('svg_experimental_source.rb','svg_experimental_context.rb','svg_experimental_original_context.rb')

class SvgExperimentalStageRun(SvgPreferenceEnumsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_EXPERIMENTAL_CORE_GETTERS'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-experimental-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_experimental_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_experimental_source']=json.loads((self.path/'svg-experimental-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in EXPERIMENTAL_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        shared=self.path/'svg_default_context.rb'
        guard='unless SvgDefaultDeclarations::CHANGES.values.include?(name)'
        text=shared.read_text()
        assert text.count(guard)==1
        shared.write_text(text.replace(guard, 'unless SvgDefaultDeclarations::CHANGES.values.include?(name) || SvgExperimentalDeclarations::NAMES.include?(name)'))
        context=self.path/'svg_onebox_context.rb'
        context.write_text(context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_experimental(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_experimental(name, warn: true)\n'))
        original=self.path/'svg_media_convert_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_experimental(name)\n')+'\nrequire_relative "svg_experimental_original_context"\n')
        (self.path/'emitted/runtime/svg_experimental.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_experimental: (String name) -> String?
  def self.read_without_experimental: (String name, ?warn: bool) -> String
end
module SvgExperimentalRead
  def self.enabled: (String name) -> bool
  def self.read: (String name) -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_experimental_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_experimental']
                assert item['reporting_improvements']['status']=='permanent'
                assert all(value['value_class']in('TrueClass','FalseClass')for value in item.values())
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for target,fault,expected in (('enable_user_menu_mentions_tab','wrong-type','SVG experimental getter result not Boolean'),('enable_user_menu_mentions_tab','wrong-result','SVG experimental source result changed'),('reporting_improvements','permanent-as-default','SVG experimental source result changed')):
            self.env.update(FIDELITY_SVG_EXPERIMENTAL_TARGET=target,FIDELITY_SVG_EXPERIMENTAL_FAULT=fault)
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-experimental-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:
                del self.env['FIDELITY_SVG_EXPERIMENTAL_TARGET'];del self.env['FIDELITY_SVG_EXPERIMENTAL_FAULT']
        self.evidence.update(actual_svg_experimental=values[0],svg_experimental_controls=controls,flag_setters_or_activation_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in EXPERIMENTAL_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgExperimentalStageRun())
