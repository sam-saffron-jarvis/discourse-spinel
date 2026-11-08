#!/usr/bin/env python3
"""Exact source preference enum reads; no mail/notification/composer/MCP actions."""
import json
import os
from probe_svg_utility_enums_stage import SvgUtilityEnumsStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle

class SvgPreferenceEnumsStageRun(SvgUtilityEnumsStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_PREFERENCE_ENUM_READS'
    extra_enum_profile='preference-enums'

    def verify_continuation(self):
        super().verify_continuation()
        allowed={v['setting'] for v in self.evidence['svg_enum_source']['enum_classes'] if v['class'] in {'WelcomeBannerLocation','WelcomeBannerPageVisibility','DigestEmailSiteSetting','EmailLevelSiteSetting','MailingListModeSiteSetting','PreviousRepliesSiteSetting','NewTopicDurationSiteSetting','AutoTrackDurationSiteSetting','NotificationLevelWhenReplyingSiteSetting','LikeNotificationFrequencySiteSetting','CompositionModeSiteSetting','McpOauthClientIdMetadataPolicy'}}
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['svg_enums'];assert item['welcome_banner_location']['value_class']=='String'
                values.append({key:value for key,value in item.items()if key in allowed})
        assert all(item==values[0]for item in values)
        controls={}
        for target,kind in (('welcome_banner_location','String'),('default_email_digest_frequency','Integer')):
            if target not in values[0]:continue
            self.env['FIDELITY_SVG_ENUM_TARGET']=target
            try:
                for fault,expected in (('wrong-wrapper','SVG unwrapped enum must remain '+kind),('wrong-value','SVG unwrapped enum value changed')):
                    self.env['FIDELITY_SVG_ENUM_FAULT']=fault
                    try:
                        for runtime,argv in (('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                            name=runtime+'-svg-preference-'+target+'-'+fault;code,_=self.command(name,argv,check=False,timeout=120)
                            assert code!=0 and expected in(self.path/(name+'.stderr')).read_text(),(name,code)
                            lifecycle(self,name)
                            assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                            controls[name]={'returncode':code,'all_fixtures_cleaned':True}
                    finally:del self.env['FIDELITY_SVG_ENUM_FAULT']
            finally:del self.env['FIDELITY_SVG_ENUM_TARGET']
        self.evidence.update(actual_svg_preference_enums=values[0],svg_preference_enum_controls=controls,preference_actions_or_ui_executed=False,full_settings_hash_acquired=False,full_layout_completed=False)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgPreferenceEnumsStageRun())
