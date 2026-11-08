#!/usr/bin/env python3
"""Source objects getter preserving raw default/current Array or stored String."""
import json
import os
import shutil
from probe_svg_experimental_stage import SvgExperimentalStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

OBJECTS_FILES=('svg_objects_context.rb','svg_objects_original_context.rb','svg_snapshot_context.rb')

class SvgObjectsStageRun(SvgExperimentalStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_FULL_SETTINGS_SNAPSHOT'
    full_settings_snapshot_supported=True
    expected_locale_boundary='actual SVG full settings_hash returned; icon extraction acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-objects-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_objects_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_objects_source']=json.loads((self.path/'svg-objects-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in OBJECTS_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        context=self.path/'svg_experimental_context.rb'
        context.write_text(context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_objects(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_objects(name, warn: true)\n'))
        original=self.path/'svg_experimental_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_objects(name)\n')+'\nrequire_relative "svg_objects_original_context"\n')
        (self.path/'emitted/runtime/svg_objects.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_objects: (String name) -> String?
  def self.read_without_objects: (String name, ?warn: bool) -> String
end
module SvgObjectsRead
  def self.current: () -> (String | Array[untyped])
  def self.note: (untyped value) -> nil
  def self.result: () -> (String | Array[untyped])?
  def self.read: () -> String
end
''')
        settings=self.path/'svg_settings_context.rb'
        text=settings.read_text()
        stop="    raise 'SVG settings_hash unexpectedly complete without supported full getter contract'"
        assert text.count(stop)==1
        settings.write_text(text.replace(stop,'    result'))
        signature=self.path/'emitted/runtime/svg_settings.rbs'
        signature.write_text(signature.read_text().replace('def self.settings_hash: () -> bot','def self.settings_hash: () -> Hash[Symbol, String]'))
        (self.path/'emitted/runtime/svg_snapshot.rbs').write_text('''module SvgSnapshotRead
  @count: Integer?
  def self.capture: (Hash[Symbol, String] value) -> nil
  def self.count: () -> Integer?
end
module RequestSvgBootstrap
  def self.settings_hash: () -> bot
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_objects_context"\nrequire_relative "svg_snapshot_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_objects']
                assert item['value_class']in('Array','String') and item['raw_identity'] and not item['parsed_or_validated']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-type','SVG objects raw result class changed'),('copied-result','SVG objects raw identity changed'),('nonempty-array','nonempty SVG objects Array profile unsupported'),('wrong-result','SVG objects String consumer changed')):
            self.env['FIDELITY_SVG_OBJECTS_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-objects-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_OBJECTS_FAULT']
        self.evidence.update(actual_svg_objects=values[0],svg_objects_controls=controls,objects_validation_or_setter_executed=False,full_settings_hash_acquired=True,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in OBJECTS_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgObjectsStageRun())
