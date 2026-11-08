#!/usr/bin/env python3
"""Shared application wrap(...).to_s consumer projection, NOT native wrapped getter."""
import json
import os
import shutil
from probe_svg_uncategorized_stage import SvgUncategorizedStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

WRAPPED_FILES=('original_svg_wrapped_source.rb','svg_wrapped_context.rb','svg_wrapped_original_context.rb')

class SvgWrappedStageRun(SvgUncategorizedStageRun):
    expected_svg_snapshot_calls=(1,2)
    success_status='PASS_SCOPED_ACTUAL_SVG_WRAPPED_ENUM_STRING_CONSUMER'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-wrapped-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_wrapped_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_wrapped_source']=json.loads((self.path/'svg-wrapped-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in WRAPPED_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        context=self.path/'svg_uncategorized_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_wrapped(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_wrapped(name, warn: true)\n')
        context.write_text(text)
        settings=self.path/'svg_settings_context.rb'
        settings.write_text(settings.read_text().replace('  def self.record(name, text)\n','  def self.record_without_wrapped_observation(name, text)\n'))
        original=self.path/'svg_enum_original_context.rb'
        original.write_text(original.read_text().replace('    def get_enum_class(name)\n','    def get_enum_class_without_wrapped(name)\n'))
        (self.path/'emitted/runtime/svg_wrapped.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind_without_wrapped: (String name) -> String?
  def self.read_without_wrapped: (String name, ?warn: bool) -> String
  def self.record_without_wrapped_observation: (String name, String text) -> String
end
module SvgWrappedRead
  @text: String?
  def self.raw: () -> String
  def self.consumer_string: () -> String
  def self.note: (String text) -> nil
  def self.text: () -> String?
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_wrapped_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_uncategorized_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_wrapped_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_wrapped_consumer'];assert item['value_class']=='String' and not item['frozen'] and item['fresh_from_raw_current']
                values.append(item)
        assert all(item==values[0]for item in values)
        reference=[json.loads(line.split(' ',1)[1])for line in(self.path/'compat-original.stdout').read_text().splitlines()if line.startswith('FIDELITY_SVG_WRAPPED_REFERENCE ')]
        assert len(reference)==self.expected_svg_snapshot_calls[-1] and all(item['string_subclass'] and item['real_source_wrap_executed'] and not item['frozen']for item in reference)
        controls={}
        for fault,expected in (('alias-current','SVG wrapped consumer String aliases raw current'),('frozen-result','SVG wrapped consumer String frozen'),('wrong-value','SVG wrapped consumer String value changed')):
            self.env['FIDELITY_SVG_WRAPPED_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-wrapped-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_WRAPPED_FAULT']
        self.evidence.update(actual_svg_wrapped_consumer=values[0],actual_original_wrapper=reference,svg_wrapped_controls=controls,generic_native_wrapped_getter_supported=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in WRAPPED_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgWrappedStageRun())
