#!/usr/bin/env python3
"""Actual common/desktop head_tag field lookup, including absent-field nil entries."""
import json
import os
import shutil
from probe_core_preload_stage import CorePreloadStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

HEAD_FILES = ('head_tag_helpers.rb','original_head_tag_helpers.rb','head_tag_context.rb','head_tag_original_context.rb')
FIELD_PATTERN = r'-?[0-9]+:(?:translations:[A-Za-z_-]+|(?:common|desktop):head_tag):[a-f0-9]{40}'

class HeadTagStageRun(CorePreloadStageRun):
    field_cache_key_pattern = FIELD_PATTERN
    success_status = 'PASS_SCOPED_ACTUAL_THEME_HEAD_TAG_BULK_BEFORE_ANALYTICS'
    expected_locale_boundary = 'analytics helper acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-head-tag-stage',['bundle','exec','ruby',HERE/'tools/generate_head_tag_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['head_tag_source']=json.loads((self.path/'head-tag-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in HEAD_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        transport=self.path/'theme_bulk_transport.rb'
        text=transport.read_text().replace('-?[0-9]+:translations:[A-Za-z_-]+:[a-f0-9]{40}',FIELD_PATTERN)
        transport.write_text(text)
        signature=self.path/'emitted/runtime/theme_lookup.rbs'
        text=signature.read_text().replace('Symbol field,','String | Symbol field,')
        text=text.replace('  def self.last_keys:', '  def self.all_keys: () -> Array[Array[Array[Integer | Symbol]]]\n  def self.last_keys:')
        signature.write_text(text)
        bus=self.path/'category_cache_bus_source.rb'
        text=bus.read_text().replace('def set(hash, key, value);','def set(hash, key, value); return if ENV.fetch("FIDELITY_HEAD_TAG_FAULT", "") == "omit-nil-publication" && value.nil? && key.include?(":head_tag:");')
        bus.write_text(text)
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "head_tag_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'core_preload_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "head_tag_original_context"\n')

    def normalize_stage_record(self,row):
        nonce=row['template_prefix']['csp_nonce']
        item=row['template_prefix']['head_tag'];item['value']=item['value'].replace(nonce,'[genuine-random-nonce]')
        return super().normalize_stage_record(row)

    def verify_continuation(self):
        super().verify_continuation()
        observations=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[]
            for row in rows:
                item=row['template_prefix']['head_tag'];item['value']=item['value'].replace(row['template_prefix']['csp_nonce'],'[genuine-random-nonce]')
                assert item['rows']==item['callbacks'] and len(item['all_query_keys'])>=2
                items.append(item)
            observations.append(items)
        assert observations[0]==observations[1]==observations[2]
        self.env['FIDELITY_HEAD_TAG_FAULT']='omit-nil-publication';controls={}
        try:
            for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-head-tag-omit-nil-publication';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'missing category cache publication'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_HEAD_TAG_FAULT']
        self.evidence.update(actual_head_tag=observations[0],head_tag_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in HEAD_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(HeadTagStageRun())
