#!/usr/bin/env python3
"""Actual source markdown feature guard and plugin head helper on native layout."""
import json
import os
import shutil
from urllib.parse import urlsplit, parse_qsl, urlencode
from probe_head_yield_stage import HeadYieldStageRun
from probe_list_body_stage import execute
from probe_category_cache_stage import lifecycle
from verify import HERE, ROOT, digest

MARKDOWN_FILES=('original_markdown_modifier_dispatch.rb','markdown_link_helpers.rb','original_markdown_link_helpers.rb','markdown_link_context.rb','markdown_link_original_context.rb','markdown_setting_context.rb','markdown_setting_original_context.rb')

class MarkdownLinkStageRun(HeadYieldStageRun):
    success_status='PASS_SCOPED_ACTUAL_MARKDOWN_GUARD_BEFORE_CLIENT_SETUP_TAG'
    expected_locale_boundary='client setup tag builder acquisition pending'

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-markdown-link-stage',['bundle','exec','ruby',HERE/'tools/generate_markdown_link_stage.rb',self.path,app],cwd=ROOT/'discourse')
        self.evidence['markdown_link_source']=json.loads((self.path/'markdown-link-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in MARKDOWN_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        # Preserve the already-acquired legacy tag(name, attrs) operation;
        # only no-argument tag-builder acquisition is the next boundary.
        for name, old, new in (('list_head_context.rb', 'def tag(name, options, open = false, escape = true)', 'def source_metadata_tag(name, options, open = false, escape = true)'), ('list_head_original_context.rb', 'def tag(*args, **options)', 'def source_metadata_tag(*args, **options)')):
            file=self.path/name;text=file.read_text();assert text.count(old)==1
            file.write_text(text.replace(old,new))
        body=self.path/'native_list_body.rb'
        text=body.read_text();old='@output_buffer.append=( @title )'
        assert text.count(old)==1
        body.write_text(text.replace(old,'@output_buffer.append=( source_owned_title )'))
        helper_source=ROOT/'roundhouse/runtime/ruby/action_view/view_helpers.rb'
        code=helper_source.read_text();start=code.index('    def self.tag_attr(');end=code.index('\n    end',start)+len('\n    end')
        selected=code[start:end]
        target=self.path/'emitted/runtime/action_view/view_helpers.rb'
        target.write_text(target.read_text()+'\nmodule ActionView\nmodule ViewHelpers\n'+selected+'\nend\nend\n')
        self.evidence['markdown_tag_attr_source']={'path':str(helper_source),'source_sha256':digest(helper_source.read_bytes()),'method_sha256':digest(selected.encode()),'unchanged_source':True}
        transport=self.path/'latest_html_stage_transport.rb'
        text=transport.read_text().replace('    matched.path_params.each {', '    original_query_parameters = params.dup\n    matched.path_params.each {').replace('    request.query_string = pieces[1].to_s', '    request.query_string = pieces[1].to_s\n    request.query_parameters = original_query_parameters')
        transport.write_text(text)
        (self.path/'emitted/runtime/markdown_setting.rbs').write_text('''module SiteSettings
  class PortableReadStore
    def get_markdown_endpoints_for_layout: (String site, Hash[Symbol, Integer] statuses) -> bool
  end
end
class ListBodyContext
  def source_owned_title: () -> String
end
module MarkdownLinkHelpers
  def source_markdown_alternate_url: () -> String?
  def markdown_alternate_path: () -> String?
  def markdown_query_string: (Hash[String, Roundhouse::ParamValue] query) -> String
  def source_markdown_void_link: (rel: String, type: String, href: String) -> ActionView::HtmlFragment
end
module MarkdownEndpointLayoutRead
  def enable_markdown_endpoints: (?untyped scoped_to) -> bool
end
''')
        original_setting=self.path/'markdown_link_original_context.rb'
        original_setting.write_text(original_setting.read_text()+'\nrequire_relative "markdown_setting_original_context"\n')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(','\nrequire_relative "markdown_setting_context"\nrequire_relative "markdown_link_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'head_yield_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "markdown_link_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            for row in rows:
                item=row['template_prefix']['markdown_link']
                if item['enabled']:
                    source=urlsplit(row['path']);actual=urlsplit(item['url'])
                    safe=set(self.evidence['markdown_link_source']['safe_query_keys'])
                    expected=urlencode(sorted((key,value)for key,value in parse_qsl(source.query,keep_blank_values=True)if key in safe))
                    assert actual.path==source.path+'.md' and actual.query==expected
                values.append(item)
        assert values[:2]==values[2:4]==values[4:6]
        self.env['FIDELITY_MARKDOWN_FAULT']='wrong-href';controls={}
        try:
            for runtime,argv in(('native',[self.path/'probe']),('compat',['bundle','exec','ruby',self.path/'compat/entry.rb'])):
                name=runtime+'-markdown-wrong-href';code,_=self.command(name,argv,check=False,timeout=120)
                assert code!=0 and 'actual markdown link/href mismatch'in(self.path/(name+'.stderr')).read_text(),name
                lifecycle(self,name)
                assert all(self.evidence[key][name]for key in('owned_cache_cleanup','owned_vm_source_cleanup','asset_lease_cleanup','owned_mf_source_cleanup'))
                controls[name]={'returncode':code,'all_fixtures_cleaned':True}
        finally:del self.env['FIDELITY_MARKDOWN_FAULT']
        self.evidence.update(actual_markdown_links=values[:2],markdown_controls=controls,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in MARKDOWN_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4])
    execute(MarkdownLinkStageRun())
