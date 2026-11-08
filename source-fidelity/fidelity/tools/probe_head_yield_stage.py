#!/usr/bin/env python3
"""Actual source head layout yield from completed genuine capture, not a page."""
import json
import os
import shutil
from probe_head_configuration_stage import HeadConfigurationStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

YIELD_FILES=('head_yield_source.rb','original_head_yield_source.rb','head_yield_context.rb','head_yield_original_context.rb')

class HeadYieldStageRun(HeadConfigurationStageRun):
    success_status='PASS_SCOPED_ACTUAL_CAPTURED_HEAD_YIELD_BEFORE_MARKDOWN'
    expected_locale_boundary='markdown alternate helper acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-head-yield-stage',['bundle','exec','ruby',HERE/'tools/generate_head_yield_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['head_yield_source']=json.loads((self.path/'head-yield-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in YIELD_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        # Emission treeshakes before this concrete helper is attached. Retain
        # the exact existing framework protocol rather than drop trust checks.
        source = ROOT/'roundhouse/runtime/ruby/action_view/html_fragment.rb'
        shutil.copyfile(source, self.path/'emitted/runtime/action_view/html_fragment.rb')
        self.evidence['head_yield_fragment_protocol'] = {'path':str(source), 'sha256':digest(source.read_bytes()), 'unchanged_source':True}
        (self.path/'emitted/runtime/head_yield.rbs').write_text('''class ListBodyContext
  @head_flow_fragment: ActionView::HtmlFragment?
  @head_flow_source: String?
  def get: (Symbol slot) -> ActionView::HtmlFragment
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "head_yield_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'head_configuration_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "head_yield_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['head_yield']
                assert item['bytes']>0 and item['warm_read_identity'] and item['fresh_safe_copy']
                values.append(item)
        # Head values differ by request URL, not runtime. Compare both requests.
        assert values[:2]==values[2:4]==values[4:6]
        controls={}
        for fault,expected in(('wrong-result','head view-flow return bytes changed'),('alias-return','head view-flow fresh return identity changed'),('escaped-head','captured head yield bytes changed')):
            self.env['FIDELITY_HEAD_YIELD_FAULT']=fault
            try:
                for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-head-yield-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),name
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_HEAD_YIELD_FAULT']
        self.evidence.update(actual_head_yields=values[:2],head_yield_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in YIELD_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(HeadYieldStageRun())
