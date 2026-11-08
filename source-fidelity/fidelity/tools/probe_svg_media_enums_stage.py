#!/usr/bin/env python3
"""Exact media enum values only; no S3 client/helper/transport is acquired."""
import json
import os
from probe_svg_nested_stage import SvgNestedStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle

class SvgMediaEnumsStageRun(SvgNestedStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_REGION_ENUM_GETTER'
    extra_enum_profile='media-enums'

    def generate(self):
        super().generate()
        # Only s3_region has the already source-proven nested-helper lexical
        # false-positive flag. All other source override guards stay intact.
        enum=self.path/'svg_enum_context.rb'
        text=enum.read_text();anchor="!options.key?('portable_source_override')"
        assert text.count(anchor)==1
        text=text.replace(anchor,"(!options.key?('portable_source_override') || (name == 's3_region' && SvgNestedDeclarations::SCOPES[name] == 'SiteSetting::Upload'))")
        enum.write_text(text)

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_enums']
                assert item['s3_region']['value_class']=='String'
                values.append({key:item[key]for key in ('s3_region','image_quality')if key in item})
        assert all(item==values[0]for item in values)
        controls={}
        for target,expected_type in (('s3_region','String'),('image_quality','Integer')):
            if target not in values[0]:continue
            self.env['FIDELITY_SVG_ENUM_TARGET']=target
            try:
                for fault,expected in (('wrong-wrapper','SVG unwrapped enum must remain '+expected_type),('wrong-value','SVG unwrapped enum value changed')):
                    self.env['FIDELITY_SVG_ENUM_FAULT']=fault
                    try:
                        for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                            name=runtime+'-svg-media-'+target+'-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                            assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                            lifecycle(self,name)
                            assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                            controls[name]={'returncode':code,'all_fixtures_cleaned':True}
                    finally:del self.env['FIDELITY_SVG_ENUM_FAULT']
            finally:del self.env['FIDELITY_SVG_ENUM_TARGET']
        self.evidence.update(actual_svg_media_enums=values[0],svg_media_enum_controls=controls,s3_calls_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgMediaEnumsStageRun())
