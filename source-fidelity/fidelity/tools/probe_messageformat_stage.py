#!/usr/bin/env python3
"""Actual MF locale source/VM/digest/preload; next override bundle still refuses."""
import json
import os
import shutil
from probe_locale_layout_stage import LocaleLayoutStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, Run

MF_FILES = ('messageformat_context.rb', 'messageformat_original_context.rb')

class MessageFormatStageRun(LocaleLayoutStageRun):
    success_status = 'PASS_SCOPED_LAYOUT_MAIN_MF_BEFORE_OVERRIDES'
    expected_locale_preload_links = 2
    expected_locale_boundary = 'client override bundle acquisition pending'

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-messageformat-stage', ['bundle','exec','ruby',HERE/'tools/generate_messageformat_stage.rb',app,self.path], cwd=ROOT/'discourse')
        self.evidence['messageformat_source'] = json.loads((self.path/'messageformat-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in MF_FILES: shutil.copyfile(HERE/'test'/name,self.path/name)
        (self.path/'emitted/runtime/messageformat.rbs').write_text('''module RequestMessageFormatCompiler
  def self.validate_source!: () -> String
  def self.compile: (String | Array[String] locales, String | Hash[String, untyped] messages, ?strict: bool) -> String
end
module RequestClientLocaleBootstrap
  @mf_builds: Integer?
  def self.mf_builds: () -> Integer
  def self.build_mf: (String locale) -> String
end
class LayoutAssetProcessorBackend
  def compile_messageformat: (String sources, String locales, String messages, bool strict) -> String
end
''')
        entry=self.path/'entry.rb';entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "messageformat_context"\nCategoryCacheBootstrap.configure('))

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1]) for line in (self.path/(name+'.stdout')).read_text().splitlines() if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['mf_locale'];assert item['bytes']>0 and item['builds']==1
                values.append(item)
        assert all(item==values[0] for item in values)
        controls={}
        for fault, expected in (('wrong-owner','unowned MessageFormat source fixture'),('wrong-packet','MessageFormat source member identity')):
            self.env['FIDELITY_MF_FAULT']=fault
            for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-mf-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and expected in (self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert self.evidence['owned_cache_cleanup'][name] and self.evidence['owned_vm_source_cleanup'][name] and self.evidence['owned_mf_source_cleanup'][name]
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        del self.env['FIDELITY_MF_FAULT']
        self.evidence.update(actual_mf_locale=values[0],mf_controls=controls,mf_compiler_acquired=True,actual_mf_preload_executed=True,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight' if name=='compat-preflight' else 'compat')
            if tree.exists():
                for item in MF_FILES:shutil.copyfile(self.path/item,tree/item)
        if name=='compat-original':
            entry=self.path/'compat/entry-original.rb';entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "messageformat_original_context"\nCategoryCacheBootstrap.configure('))
        binary=str(self.path/'probe')
        runtime=name.startswith('compat') or name!='native-compile' and binary in [str(x)for x in argv]
        if runtime:
            fixture=self.path/(name+'-mf-source')
            prior_root=self.env.get('FIDELITY_MF_SOURCE_ROOT');prior_owner=self.env.get('FIDELITY_SOURCE_OWNER_PID')
            self.env['FIDELITY_SOURCE_OWNER_PID']=str(os.getpid())
            try:
                Run.command(self,'mf-source-'+name,['bundle','exec','ruby',HERE/'tools/materialize_messageformat_source.rb',fixture],cwd=ROOT/'discourse',timeout=30)
                fault=self.env.get('FIDELITY_MF_FAULT','')
                if fault=='wrong-owner':
                    file=fixture/'source-lease.json';item=json.loads(file.read_text());item['owner_pid']+=1;file.write_text(json.dumps(item))
                if fault=='wrong-packet':(fixture/'source-packet.json').write_text('[]')
                self.env['FIDELITY_MF_SOURCE_ROOT']=str(fixture)
                return super().command(name,argv,**kwargs)
            finally:
                if prior_root is None:self.env.pop('FIDELITY_MF_SOURCE_ROOT',None)
                else:self.env['FIDELITY_MF_SOURCE_ROOT']=prior_root
                if prior_owner is None:self.env.pop('FIDELITY_SOURCE_OWNER_PID',None)
                else:self.env['FIDELITY_SOURCE_OWNER_PID']=prior_owner
                if fixture.exists():shutil.rmtree(fixture)
                self.evidence.setdefault('owned_mf_source_cleanup',{})[name]=not fixture.exists()
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(MessageFormatStageRun())
