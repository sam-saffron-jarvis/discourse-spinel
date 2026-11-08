#!/usr/bin/env python3
"""Actual Emoji/String and TrustLevel/Integer no-wrap enum consumer contracts."""
import json
import os
from probe_svg_wrapped_stage import SvgWrappedStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle

class SvgNoticeEnumsStageRun(SvgWrappedStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_EMOJI_AND_NOTICE_ENUM_TYPES'
    extra_enum_profile='notice-enums'

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_enums']
                assert item['emoji_set']['value_class']=='String'
                assert item['new_user_notice_tl']['value_class']=='Integer' and item['returning_user_notice_tl']['value_class']=='Integer'
                values.append({key:item[key]for key in ('emoji_set','new_user_notice_tl','returning_user_notice_tl')})
        assert all(item==values[0]for item in values)
        controls={};self.env['FIDELITY_SVG_ENUM_TARGET']='new_user_notice_tl'
        try:
            for fault,expected in (('wrong-wrapper','SVG unwrapped enum must remain Integer'),('wrong-value','SVG unwrapped enum value changed')):
                self.env['FIDELITY_SVG_ENUM_FAULT']=fault
                try:
                    for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                        name=runtime+'-svg-integer-enum-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                        assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                        lifecycle(self,name)
                        assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                        controls[name]={'returncode':code,'all_fixtures_cleaned':True}
                finally:del self.env['FIDELITY_SVG_ENUM_FAULT']
        finally:del self.env['FIDELITY_SVG_ENUM_TARGET']
        self.evidence.update(actual_svg_notice_enums=values[0],svg_notice_enum_controls=controls,full_settings_hash_acquired=False,full_layout_completed=False)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgNoticeEnumsStageRun())
