#!/usr/bin/env python3
"""Three source-pinned unwrapped enum getter contracts in SVG settings consumer."""
import json
import os
import shutil
from probe_svg_top_menu_stage import SvgTopMenuStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

ENUM_FILES=('svg_enum_declarations.rb','original_svg_enum_source.rb','svg_enum_context.rb','svg_enum_original_context.rb')

class SvgEnumStageRun(SvgTopMenuStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_SETTINGS_UNWRAPPED_ENUMS'
    extra_enum_profile=None

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        argv=['bundle','exec','ruby',HERE/'tools/generate_svg_enum_stage.rb',self.path]
        if self.extra_enum_profile:argv.append(self.extra_enum_profile)
        self.command('generate-svg-enum-stage',argv,cwd=ROOT/'discourse')
        self.evidence['svg_enum_source']=json.loads((self.path/'svg-enum-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in ENUM_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        menu=self.path/'svg_top_menu_context.rb'
        text=menu.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_enums(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_enums(name, warn: true)\n')
        menu.write_text(text)
        (self.path/'emitted/runtime/svg_enums.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_enums: (String name) -> String?
  def self.read_without_enums: (String name, ?warn: bool) -> String
end
module SvgEnumRead
  def self.current: (String name) -> untyped
  def self.read: (String name) -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_enum_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_top_menu_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_enum_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_enums']
                expected_types={v['setting']:v['expected_return_class']for v in self.evidence['svg_enum_source']['enum_classes']}
                assert {'desktop_category_page_style','mobile_category_page_style'}<=set(item) and all(v['value_class']==expected_types[key]for key,v in item.items())
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-wrapper','SVG unwrapped enum must remain String'),('wrong-value','SVG unwrapped enum value changed')):
            self.env['FIDELITY_SVG_ENUM_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-enum-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_ENUM_FAULT']
        self.evidence.update(actual_svg_enums=values[0],svg_enum_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in ENUM_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgEnumStageRun())
