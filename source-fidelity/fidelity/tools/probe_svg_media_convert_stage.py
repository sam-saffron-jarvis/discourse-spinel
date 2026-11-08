#!/usr/bin/env python3
"""Exact media-convert upcoming GETTER, never conversion/setting action."""
import json
import os
import shutil
from probe_svg_uploaded_list_stage import SvgUploadedListStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

CONVERT_FILES=('svg_media_convert_source.rb','svg_media_convert_context.rb','svg_media_convert_original_context.rb')

class SvgMediaConvertStageRun(SvgUploadedListStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_MEDIA_CONVERT_UPCOMING_GETTER'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-media-convert-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_uncategorized_stage.rb',self.path,'media-convert'],cwd=ROOT/'discourse')
        self.evidence['svg_media_convert_source']=json.loads((self.path/'svg-media-convert-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for source,target in (('svg_uncategorized_context.rb','svg_media_convert_context.rb'),('svg_uncategorized_original_context.rb','svg_media_convert_original_context.rb')):
            text=(HERE/'test'/source).read_text()
            for old,new in (('SvgUncategorized','SvgMediaConvert'),('without_uncategorized','without_media_convert'),('svg_uncategorized','svg_media_convert'),('SVG uncategorized','SVG media-convert'),('FIDELITY_SVG_UNCATEGORIZED','FIDELITY_SVG_MEDIA_CONVERT'),('remove_and_replace_uncategorized','composer_media_optimization_image_convert_enabled'),('svg_local_login_stage_observation','svg_uploaded_list_stage_observation')):
                text=text.replace(old,new)
            (self.path/target).write_text(text)
        context=self.path/'svg_uploaded_list_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_media_convert(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_media_convert(name, warn: true)\n')
        context.write_text(text)
        original=self.path/'svg_uploaded_list_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_media_convert(name)\n'))
        (self.path/'emitted/runtime/svg_media_convert.rbs').write_text('''module SiteSettings
  class PortableReadStore
    def get_svg_media_convert_change: (String site, Hash[Symbol, Integer] statuses) -> bool
  end
end
module SvgSettingsRead
  def self.additional_kind_without_media_convert: (String name) -> String?
  def self.read_without_media_convert: (String name, ?warn: bool) -> String
end
module SvgMediaConvertRead
  def self.enabled: () -> bool
  def self.read: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_media_convert_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_uploaded_list_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_media_convert_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_media_convert'];assert item['getter_only'] and not item['setter_or_action_invoked']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('non-boolean','SVG media-convert getter result not Boolean'),('wrong-result','SVG media-convert upcoming getter changed')):
            self.env['FIDELITY_SVG_MEDIA_CONVERT_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-media-convert-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_MEDIA_CONVERT_FAULT']
        self.evidence.update(actual_svg_media_convert=values[0],svg_media_convert_controls=controls,media_conversion_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in CONVERT_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgMediaConvertStageRun())
