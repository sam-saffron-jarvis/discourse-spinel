#!/usr/bin/env python3
"""Source remove/replace-uncategorized GETTER only, never toggle/action/write."""
import json
import os
import shutil
from probe_svg_full_name_stage import SvgFullNameStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

UNCAT_FILES=('svg_uncategorized_source.rb','svg_uncategorized_context.rb','svg_uncategorized_original_context.rb')

class SvgUncategorizedStageRun(SvgFullNameStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_UNCATEGORIZED_CHANGE_GETTER'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-uncategorized-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_uncategorized_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_uncategorized_source']=json.loads((self.path/'svg-uncategorized-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in UNCAT_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        context=self.path/'svg_local_login_context.rb'
        text=context.read_text().replace('  def self.additional_kind(name)\n','  def self.additional_kind_without_uncategorized(name)\n').replace('  def self.read(name, warn: true)\n','  def self.read_without_uncategorized(name, warn: true)\n')
        context.write_text(text)
        original=self.path/'svg_local_login_original_context.rb'
        original.write_text(original.read_text().replace('    def acquired_getter_value(name)\n','    def acquired_getter_value_without_uncategorized(name)\n'))
        (self.path/'emitted/runtime/svg_uncategorized.rbs').write_text('''module SiteSettings
  class PortableReadStore
    def get_svg_uncategorized_change: (String site, Hash[Symbol, Integer] statuses) -> bool
  end
end
module SvgSettingsRead
  def self.additional_kind_without_uncategorized: (String name) -> String?
  def self.read_without_uncategorized: (String name, ?warn: bool) -> String
end
module SvgUncategorizedRead
  def self.enabled: () -> bool
  def self.read: () -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_uncategorized_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_local_login_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_uncategorized_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_uncategorized'];assert item['getter_only'] and not item['setter_or_action_invoked']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('non-boolean','SVG uncategorized getter result not Boolean'),('wrong-result','SVG uncategorized upcoming getter changed')):
            self.env['FIDELITY_SVG_UNCATEGORIZED_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-uncategorized-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_UNCATEGORIZED_FAULT']
        self.evidence.update(actual_svg_uncategorized=values[0],svg_uncategorized_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in UNCAT_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgUncategorizedStageRun())
