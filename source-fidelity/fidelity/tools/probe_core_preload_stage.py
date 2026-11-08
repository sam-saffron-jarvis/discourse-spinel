#!/usr/bin/env python3
"""Actual browser script and source-built module preloads on native layout path."""
import json
import os
import shutil
from probe_theme_lookup_stage import ThemeLookupStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

CORE_FILES = ('core_preload_helpers.rb','original_core_preload_helpers.rb','core_preload_context.rb','core_preload_original_context.rb')

class CorePreloadStageRun(ThemeLookupStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_CORE_PRELOADS_BEFORE_THEME_HEAD_TAG'
    expected_locale_boundary = 'Theme head_tag bulk acquisition pending'
    expected_locale_preload_links = 3

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-core-preload-stage',['bundle','exec','ruby',HERE/'tools/generate_core_preload_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['core_preload_source'] = json.loads((self.path/'core-preload-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in CORE_FILES:
            file = HERE/'test'/name
            if file.exists(): shutil.copyfile(file,self.path/name)
        (self.path/'emitted/runtime/core_preload.rbs').write_text('''module CorePreloadHelpers
  def source_preload_script: (String script, ?type_module: bool, ?attrs: Hash[String | Symbol, String]) -> ActionView::HtmlFragment
  def source_module_preloads_for: (*String? scripts) -> ActionView::HtmlFragment
end
module CorePreloadViewProtocol
  def preload_script: (String script, ?type_module: bool, ?attrs: Hash[String | Symbol, String]) -> ActionView::HtmlFragment
  def module_preloads_for: (*String? scripts) -> ActionView::HtmlFragment
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "core_preload_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'theme_lookup_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "core_preload_original_context"\n')

    def normalize_stage_record(self,row):
        nonce=row['template_prefix']['csp_nonce']
        core=row['template_prefix']['core_preloads']
        for name in ('browser_markup','module_markup'): core[name]=core[name].replace(nonce,'[genuine-random-nonce]')
        return super().normalize_stage_record(row)

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in (self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['core_preloads']
                for key in ('browser_markup','module_markup'): item[key]=item[key].replace(row['template_prefix']['csp_nonce'],'[genuine-random-nonce]')
                assert item['chunks'] and len(item['chunks'])==len(item['urls'])
                values.append(item)
        assert all(item==values[0]for item in values)
        self.env['FIDELITY_CORE_PRELOAD_FAULT']='omit-modules'
        controls={}
        try:
            for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-core-omit-modules';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'actual core module preload missing'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in ('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally: del self.env['FIDELITY_CORE_PRELOAD_FAULT']
        self.evidence.update(actual_core_preloads=values[0],core_preload_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else 'compat')
            if tree.exists():
                for item in CORE_FILES: shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(CorePreloadStageRun())
