#!/usr/bin/env python3
"""AST lexical owner proof for generated settings, never nested S3 helper calls."""
import json
import os
import shutil
from probe_svg_choice_list_stage import SvgChoiceListStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

NESTED_FILES=('svg_nested_declarations.rb','svg_nested_context.rb','svg_nested_original_context.rb')

class SvgNestedStageRun(SvgChoiceListStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_GENERATED_GETTER_LEXICAL_OWNERS'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-nested-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_nested_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_nested_source']=json.loads((self.path/'svg-nested-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in NESTED_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        context=self.path/'svg_choice_list_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_nested(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_nested(name, warn: true)\n')
        context.write_text(text)
        (self.path/'emitted/runtime/svg_nested.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_nested: (String name) -> String?
  def self.read_without_nested: (String name, ?warn: bool) -> String
end
module SvgNestedRead
  def self.supported?: (String name) -> bool
  def self.current: (String name) -> untyped
  def self.read: (String name) -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_nested_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_choice_list_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_nested_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_lexical_getters'];assert 'enable_s3_uploads' in item and item['enable_s3_uploads']['raw_class']=='FalseClass'
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-type','SVG generated scalar getter raw type changed'),('wrong-value','SVG generated scalar getter value changed')):
            self.env['FIDELITY_SVG_NESTED_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-lexical-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_NESTED_FAULT']
        self.evidence.update(actual_svg_lexical_getters=values[0],svg_nested_controls=controls,s3_calls_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in NESTED_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgNestedStageRun())
