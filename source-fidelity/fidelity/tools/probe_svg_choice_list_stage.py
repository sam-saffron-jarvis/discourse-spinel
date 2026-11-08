#!/usr/bin/env python3
"""Actual explicit list with enum choices, NOT an enum wrapper or Locale UI boot."""
import json
import os
import shutil
from probe_svg_notice_enums_stage import SvgNoticeEnumsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE

CHOICE_FILES=('svg_choice_list_context.rb','svg_choice_list_original_context.rb')

class SvgChoiceListStageRun(SvgNoticeEnumsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_EXPLICIT_LIST_CHOICE_GETTER'

    def generate(self):
        super().generate()
        for name in CHOICE_FILES:shutil.copyfile(HERE/'test'/name,self.path/name)
        context=self.path/'svg_wrapped_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_choice_list(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_choice_list(name, warn: true)\n')
        context.write_text(text)
        original=self.path/'svg_wrapped_original_context.rb'
        original.write_text(original.read_text().replace('    def get_enum_class(name)\n','    def get_enum_class_without_choice_list(name)\n'))
        (self.path/'emitted/runtime/svg_choice_list.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_choice_list: (String name) -> String?
  def self.read_without_choice_list: (String name, ?warn: bool) -> String
end
module SvgChoiceListRead
  def self.current: () -> untyped
  def self.read: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_choice_list_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_wrapped_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_choice_list_original_context"\n')
        self.evidence['svg_choice_list_contract']={'setting':'content_localization_supported_locales','type':'list','choices_enum':'LocaleSiteSetting','source_type_precedence':'TypeSupervisor.load_setting opts[:type] ||= :enum preserves explicit :list','original_enum_class_lookup_for_getter_refuses':True,'locale_ui_or_validation_executed':False,'full_settings_boot':False}

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_choice_list'];assert item['value_class']=='String' and not item['choice_class_used_for_getter_wrap']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('array-result','SVG explicit list getter must remain String'),('wrong-value','SVG explicit list getter value changed')):
            self.env['FIDELITY_SVG_CHOICE_LIST_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-choice-list-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_CHOICE_LIST_FAULT']
        self.evidence.update(actual_svg_choice_list=values[0],svg_choice_list_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in CHOICE_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgChoiceListStageRun())
