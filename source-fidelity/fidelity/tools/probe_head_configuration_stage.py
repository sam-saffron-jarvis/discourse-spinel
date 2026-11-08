#!/usr/bin/env python3
"""Actual source analytics/manifest/iOS helper execution before head layout yield."""
import json
import os
import shutil
from probe_head_tag_stage import HeadTagStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

CONFIG_FILES = ('head_configuration_helpers.rb','original_head_configuration_helpers.rb','head_configuration_context.rb','head_configuration_original_context.rb')

class HeadConfigurationStageRun(HeadTagStageRun):
    success_status = 'PASS_SCOPED_ACTUAL_HEAD_CONFIGURATION_BEFORE_LAYOUT_YIELD'
    expected_locale_boundary = 'original layout_for head view-flow acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-head-configuration-stage',['bundle','exec','ruby',HERE/'tools/generate_head_configuration_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['head_configuration_source']=json.loads((self.path/'head-configuration-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in CONFIG_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "head_configuration_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'head_tag_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "head_configuration_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:values.append(row['template_prefix']['head_configuration'])
        assert all(item==values[0]for item in values)
        self.env['FIDELITY_HEAD_CONFIG_FAULT']='wrong-manifest';controls={}
        try:
            for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-head-config-wrong-manifest';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'actual manifest URL mismatch'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_HEAD_CONFIG_FAULT']
        self.evidence.update(actual_head_configuration=values[0],head_configuration_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in CONFIG_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(HeadConfigurationStageRun())
