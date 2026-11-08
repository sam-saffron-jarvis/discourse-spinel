#!/usr/bin/env python3
"""Source utility enum getters, never navigation/backup/search/UI actions."""
import json
import os
from probe_svg_review_enums_stage import SvgReviewEnumsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle

class SvgUtilityEnumsStageRun(SvgReviewEnumsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_UTILITY_ENUM_GETTERS'
    extra_enum_profile='utility-enums'

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        classes={'NavigationMenuSiteSetting','BackupLocationSiteSetting','SearchSortOrderSiteSetting','SearchExperienceSiteSetting','SlugSetting'}
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_enums'];assert item['navigation_menu']['value_class']=='String'
                values.append({key:value for key,value in item.items()if value['enum_class']in classes})
        assert all(item==values[0]for item in values)
        controls={};self.env['FIDELITY_SVG_ENUM_TARGET']='navigation_menu'
        try:
            for fault,expected in (('wrong-wrapper','SVG unwrapped enum must remain String'),('wrong-value','SVG unwrapped enum value changed')):
                self.env['FIDELITY_SVG_ENUM_FAULT']=fault
                try:
                    for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                        name=runtime+'-svg-utility-enum-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                        assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                        lifecycle(self,name)
                        assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                        controls[name]={'returncode':code,'all_fixtures_cleaned':True}
                finally:del self.env['FIDELITY_SVG_ENUM_FAULT']
        finally:del self.env['FIDELITY_SVG_ENUM_TARGET']
        self.evidence.update(actual_svg_utility_enums=values[0],svg_utility_enum_controls=controls,utility_ui_or_actions_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgUtilityEnumsStageRun())
