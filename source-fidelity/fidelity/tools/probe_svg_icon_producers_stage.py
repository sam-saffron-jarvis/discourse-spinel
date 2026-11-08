#!/usr/bin/env python3
"""Actual SVG settings/plugin/badge/group producers, real cold and warm cache."""
import json
import os
import shutil
from pathlib import Path
from probe_svg_objects_stage import SvgObjectsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

PRODUCER_FILES=('svg_icon_producers_metadata.rb','svg_icon_producers_source.rb','original_svg_icon_producers_source.rb','original_svg_icon_producers_metadata.rb','svg_icon_producers_context.rb','svg_icon_producers_original_context.rb')

class SvgIconProducersStageRun(SvgObjectsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_ICON_PRODUCERS'
    svg_icon_producers_supported=True
    expected_svg_snapshot_calls=(1,1)
    expected_locale_boundary='actual SVG settings/plugin/badge/group icons acquired; theme icon acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-icon-producers-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_icon_producers_stage.rb',self.path],cwd=ROOT/'discourse')
        proof=json.loads((self.path/'svg-icon-producers-source-proof.json').read_text());self.evidence['svg_icon_producers_source']=proof
        serving=Path(self.asset_provenance['root'])
        for relative,expected in proof['sources'].items():
            assert digest((serving/relative).read_bytes())==expected
            self.asset_provenance['files'][relative]=expected
        (self.path/'asset-serving-provenance.json').write_text(json.dumps(self.asset_provenance,indent=2)+'\n')
        self.evidence['asset_serving_provenance'].update(file_count=len(self.asset_provenance['files']),sha256=digest((self.path/'asset-serving-provenance.json').read_bytes()))

    def generate(self):
        super().generate()
        for name in PRODUCER_FILES:
            source=HERE/'test'/name
            if source.exists():shutil.copyfile(source,self.path/name)
        for name in ('svg_snapshot.rbs','svg_cache.rbs'):
            signature=self.path/'emitted/runtime'/name
            signature.write_text(signature.read_text().replace('def self.settings_hash: () -> bot','def self.settings_hash: () -> Hash[Symbol, String]'))
        (self.path/'emitted/runtime/svg_icon_producers.rbs').write_text('''module SvgIconProducers
  @types: SvgIconReadTypes?
  @cached_on_entry: bool?
  @expected_settings_icons: Array[String]?
  def self.types: () -> SvgIconReadTypes
  def self.cached_on_entry: () -> bool?
  def self.note_entry: () -> nil
  def self.note_settings_input: (Hash[Symbol, String] value) -> nil
  def self.expected_settings_icons: () -> Array[String]?
  def self.wait_for_values: () -> nil
  def self.source_settings_icons: () -> Array[String?]
  def self.source_badge_icons: () -> Array[String?]
  def self.source_group_icons: () -> Array[String?]
end
class SvgIconReadTypes
  def get_type: (Symbol name) -> Symbol?
  def type_hash: (Symbol name) -> Hash[Symbol, untyped]
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_icon_producers_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'svg_objects_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_icon_producers_original_context"\n')

    def compat_diagnostic(self):
        super().compat_diagnostic()
        controls={}
        tests=(('FIDELITY_SVG_UPLOADED_LIST_FAULT','memoized-empty','SVG uploaded-image-list empty branch incorrectly memoized'),('FIDELITY_SVG_OBJECTS_FAULT','wrong-result','SVG objects String consumer changed'),('FIDELITY_SVG_PRODUCERS_FAULT','wrong-settings','SVG settings producer source input changed'),('FIDELITY_SVG_PRODUCERS_FAULT','wrong-type','SVG icon computation type'),('FIDELITY_SVG_PRODUCERS_FAULT','nonempty-objects','nonempty SVG object property walk unacquired'))
        for variable,fault,expected in tests:
            self.env[variable]=fault
            try:
                name='compat-preflight-svg-'+variable.lower()+'-'+fault
                code,_=self.command(name,['bundle','exec','ruby',self.path/'compat-preflight/entry.rb'],check=False,timeout=120)
                assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env[variable]
        self.evidence['svg_producer_focused_preflight_controls']=controls

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            items=[row['template_prefix']['svg_icon_producers']for row in rows]
            assert len(items)==2 and items[0]==items[1]
            assert items[0]['warm_identity'] and not items[0]['warm_republished'] and items[0]['real_nullable_group_icon']
            values.append(items[0])
        assert all(value==values[0]for value in values)
        controls={}
        for fault,expected in (('wrong-settings','SVG settings producer source input changed'),('wrong-type','SVG icon computation type'),('nonempty-objects','nonempty SVG object property walk unacquired')):
            self.env['FIDELITY_SVG_PRODUCERS_FAULT']=fault
            try:
                for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                    name=runtime+'-svg-producers-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                    assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                    lifecycle(self,name)
                    assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                    controls[name]={'returncode':code,'all_fixtures_cleaned':True}
            finally:del self.env['FIDELITY_SVG_PRODUCERS_FAULT']
        self.evidence.update(actual_svg_icon_producers=values[0],svg_icon_producer_controls=controls,svg_pg_queries_acquired=True,svg_settings_icons_acquired=True,full_settings_hash_acquired=True,svg_xml_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in PRODUCER_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgIconProducersStageRun())
