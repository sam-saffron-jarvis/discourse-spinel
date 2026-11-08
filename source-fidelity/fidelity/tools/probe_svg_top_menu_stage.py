#!/usr/bin/env python3
"""Reuse independently acquired source top_menu default/promotion in SVG consumer."""
import json
import os
import shutil
from probe_svg_legacy_stage import SvgLegacyStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE

MENU_FILES=('svg_top_menu_context.rb','svg_top_menu_original_context.rb')

class SvgTopMenuStageRun(SvgLegacyStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_SETTINGS_TOP_MENU_GETTER'

    def generate(self):
        super().generate()
        for name in MENU_FILES:shutil.copyfile(HERE/'test'/name,self.path/name)
        legacy=self.path/'svg_legacy_context.rb'
        legacy.write_text(legacy.read_text().replace('  def self.read(name, warn: true)\n','  def self.read_with_legacy(name, warn: true)\n'))
        (self.path/'emitted/runtime/svg_top_menu.rbs').write_text('''module SvgSettingsRead
  def self.additional_kind: (String name) -> String?
  def self.read_with_legacy: (String name, ?warn: bool) -> String
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_top_menu_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_legacy_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_top_menu_original_context"\n')
        self.evidence['svg_top_menu_reuse']={'candidate':'existing SiteSetting.top_menu/get_top_menu_for_html guarded source-specific reader','reference':'raw original UpcomingChanges.enabled? and DefaultsProvider activation/all/current modified precedence','raw_default_supplied_as_input':False,'whole_settings_boot':False}

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_top_menu']
                assert item['source_named_getter'] and not item['raw_default_substituted']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={};self.env['FIDELITY_SVG_TOP_MENU_FAULT']='raw-default'
        try:
            for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-svg-top-menu-raw-default';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'SVG top_menu special getter bypassed' in(self.path/(name+'.stderr')).read_text(),(name,code)
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_SVG_TOP_MENU_FAULT']
        self.evidence.update(actual_svg_top_menu=values[0],svg_top_menu_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in MENU_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgTopMenuStageRun())
