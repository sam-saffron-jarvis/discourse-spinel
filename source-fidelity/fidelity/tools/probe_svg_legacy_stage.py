#!/usr/bin/env python3
"""Source deprecated warn:false aliases in the actual settings_hash consumer."""
import json
import os
import shutil
from probe_svg_settings_stage import SvgSettingsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT

LEGACY_FILES=('svg_legacy_source.rb','original_svg_legacy_source.rb','svg_legacy_context.rb','svg_legacy_original_context.rb')

class SvgLegacyStageRun(SvgSettingsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_SETTINGS_DEPRECATED_GETTERS'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-legacy-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_legacy_stage.rb',self.path],cwd=ROOT/'discourse')
        self.evidence['svg_legacy_source']=json.loads((self.path/'svg-legacy-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in LEGACY_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        context=self.path/'svg_settings_context.rb'
        text=context.read_text().replace('  def self.bind\n','  def self.bind_without_legacy_audit\n').replace('  def self.read(name)\n','  def self.read_plain_or_upload(name)\n')
        text=text.replace('result[name.to_sym] = record(name, read(name))', "result[name.to_sym] = record(name, SvgLegacyDeclarations::ALIASES.key?(name) ? read(name, warn: false) : read(name))")
        context.write_text(text)
        rbs=self.path/'emitted/runtime/svg_settings.rbs'
        rbs.write_text(rbs.read_text().replace('def self.read: (String name) -> String','def self.read: (String name, ?warn: bool) -> String\n  def self.read_plain_or_upload: (String name) -> String\n  def self.bind_without_legacy_audit: () -> nil'))
        (self.path/'emitted/runtime/svg_legacy.rbs').write_text('''module SvgLegacyRead
  @calls: Array[String]?
  def self.reset: () -> nil
  def self.calls: () -> Array[String]
  def self.note: (String name, String target, bool warn) -> nil
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_legacy_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_settings_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_legacy_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_legacy']
                assert item['calls'] and item['warn_false'] and not item['alias_forwarded_to_replacement']
                values.append(item)
        assert all(item==values[0]for item in values)
        controls={}
        for fault,expected in (('wrong-warning','unsupported SVG deprecated warning profile'),('replacement-getter','SVG deprecated alias selected wrong source getter')):
            self.env['FIDELITY_SVG_LEGACY_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-legacy-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'expected_error':expected,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_LEGACY_FAULT']
        self.evidence.update(actual_svg_legacy=values[0],svg_legacy_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in LEGACY_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgLegacyStageRun())
