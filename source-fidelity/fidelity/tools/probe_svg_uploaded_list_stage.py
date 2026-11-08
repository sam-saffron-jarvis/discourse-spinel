#!/usr/bin/env python3
"""Actual uploaded-image-list empty source branch, fresh Array/no fake cache hit."""
import json
import os
import shutil
from probe_svg_media_enums_stage import SvgMediaEnumsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE

UPLOADED_FILES=('svg_uploaded_list_context.rb','svg_uploaded_list_original_context.rb')

class SvgUploadedListStageRun(SvgMediaEnumsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_UPLOADED_IMAGE_LIST_EMPTY_GETTER'
    expected_svg_snapshot_calls=(1,2)

    def generate(self):
        super().generate()
        for name in UPLOADED_FILES:shutil.copyfile(HERE/'test'/name,self.path/name)
        context=self.path/'svg_nested_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_uploaded_list(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_uploaded_list(name, warn: true)\n')
        context.write_text(text)
        original=self.path/'svg_uncategorized_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_uploaded_list(name)\n'))
        (self.path/'emitted/runtime/svg_uploaded_list.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_uploaded_list: (String name) -> String?
  def self.read_without_uploaded_list: (String name, ?warn: bool) -> String
end
module SvgUploadedListRead
  @prior_array: untyped
  @last_array: Array[untyped]?
  @calls: Integer?
  def self.assert_empty_input: () -> nil
  def self.note_array: (untyped value) -> nil
  def self.calls: () -> Integer
  def self.read: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_uploaded_list_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_nested_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_uploaded_list_original_context"\n')
        self.evidence['svg_uploaded_list_contract']={'setting':'selectable_avatars','source_branch':'actual empty current String -> return [] before uploads cache assignment','reference':'raw original setup_methods uploaded_image_list branch','nonempty_profile':'explicit refusal before unacquired rows/stringification','source_settings_boot':False,'fake_seed_or_preload':False}

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[row['template_prefix']['svg_uploaded_list']for row in rows]
            assert len(items)==2 and [v['source_array_calls']for v in items]==list(self.expected_svg_snapshot_calls)
            assert all(v['source_input_empty'] and v['actual_empty_array'] and v['fresh_array_each_call'] and not v['empty_branch_memoized']for v in items)
            values.append(items)
        assert values[0]==values[1]==values[2]
        controls={}
        for fault,expected in (('memoized-empty','SVG uploaded-image-list empty branch incorrectly memoized'),('string-result','SVG uploaded-image-list getter must return Array')):
            self.env['FIDELITY_SVG_UPLOADED_LIST_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-uploaded-list-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_UPLOADED_LIST_FAULT']
        self.evidence.update(actual_svg_uploaded_list=values[0],svg_uploaded_list_controls=controls,nonempty_uploaded_image_list_supported=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in UPLOADED_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgUploadedListStageRun())
