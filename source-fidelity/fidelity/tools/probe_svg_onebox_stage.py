#!/usr/bin/env python3
"""Actual Onebox locale enum getter, source hierarchy/Mutex identity, no UI/network."""
import json
import os
import shutil
from pathlib import Path
from probe_svg_media_convert_stage import SvgMediaConvertStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

ONEBOX_FILES=('svg_onebox_classes.rb','original_svg_onebox_classes.rb','svg_onebox_context.rb','svg_onebox_original_context.rb')

class SvgOneboxStageRun(SvgMediaConvertStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_ONEBOX_LOCALE_READ_CONTRACT'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-onebox-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_onebox_stage.rb',self.path],cwd=ROOT/'discourse')
        proof=json.loads((self.path/'svg-onebox-source-proof.json').read_text())
        self.evidence['svg_onebox_source']=proof
        serving=Path(self.asset_provenance['root'])
        for relative,expected in proof['sources'].items():
            data=(serving/relative).read_bytes()
            assert digest(data)==expected
            self.asset_provenance['files'][relative]=expected
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in ONEBOX_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        context=self.path/'svg_media_convert_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_onebox(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_onebox(name, warn: true)\n')
        context.write_text(text)
        record=self.path/'svg_wrapped_context.rb'
        record.write_text(record.read_text().replace('  def self.record(name, text)\n','  def self.record_without_onebox(name, text)\n'))
        original=self.path/'svg_choice_list_original_context.rb'
        original.write_text(original.read_text().replace('    def get_enum_class(name)\n','    def get_enum_class_without_onebox(name)\n'))
        (self.path/'emitted/runtime/svg_onebox.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_onebox: (String name) -> String?
  def self.read_without_onebox: (String name, ?warn: bool) -> String
  def self.record_without_onebox: (String name, String text) -> String
end
module SvgOneboxRead
  @result: String?
  def self.verify_source!: () -> nil
  def self.verify_classes!: () -> nil
  def self.class_facts: () -> Hash[Symbol, bool]
  def self.current: () -> String
  def self.read: () -> String
  def self.note: (String text) -> nil
  def self.result: () -> String?
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_onebox_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_media_convert_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_onebox_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_onebox']
                assert item['value_class']=='String' and item['raw_identity']
                assert item['class_facts']=={'locks_distinct':True,'inherited_translate_names':True,'wraps':False}
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-class','Onebox getter wrong source class'),('wrapped-class','Onebox getter unexpectedly wrapped'),('aliased-lock','Onebox source locks aliased'),('wrong-source','Onebox source member changed'),('wrong-type','Onebox getter result must be String'),('copied-result','Onebox getter String identity changed'),('wrong-result','Onebox getter result changed')):
            self.env['FIDELITY_SVG_ONEBOX_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-onebox-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_ONEBOX_FAULT']
        self.evidence.update(actual_svg_onebox=values[0],svg_onebox_controls=controls,onebox_network_executed=False,locale_ui_validation_or_scan_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in ONEBOX_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgOneboxStageRun())
