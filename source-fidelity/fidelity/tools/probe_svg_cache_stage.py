#!/usr/bin/env python3
"""Actual SVG cache prefix; refuses before unacquired settings_hash getters."""
import json
import os
import shutil
from probe_client_highlight_stage import ClientHighlightStageRun
from probe_list_body_stage import execute
from verify import HERE, ROOT

SVG_FILES=('svg_cache_source.rb','original_svg_cache_source.rb','svg_cache_transport.rb','svg_cache_context.rb','svg_cache_original_context.rb')

class SvgCacheStageRun(ClientHighlightStageRun):
    success_status='PASS_SCOPED_ACTUAL_SVG_CACHE_PREFIX_BEFORE_SETTINGS_HASH'
    svg_icon_producers_supported=False
    svg_bundle_supported=False
    client_meta_supported=False
    expected_locale_boundary='source settings_hash getter acquisition pending'
    additional_schema_tables=ClientHighlightStageRun.additional_schema_tables+('badges',)

    def prepare_serialization_stage_inputs(self,app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-svg-cache-stage',['bundle','exec','ruby',HERE/'tools/generate_svg_cache_stage.rb',app,self.path],cwd=ROOT/'discourse')
        self.evidence['svg_cache_source']=json.loads((self.path/'svg-cache-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in SVG_FILES:
            file=HERE/'test'/name
            if file.exists():shutil.copyfile(file,self.path/name)
        transport=self.path/'category_cache_transport.rb'
        text=transport.read_text().replace('["category_url", "icon_manager", "scheme_hex_for_name"]','["category_url", "icon_manager", "scheme_hex_for_name", "svg_sprite"]').replace('["category_url_set", "icon_manager_set", "scheme_hex_for_name_set"]','["category_url_set", "icon_manager_set", "scheme_hex_for_name_set", "svg_sprite_set"]')
        text=text.replace('    if data["hash_key"] == "category_url"','    if data["hash_key"] == "svg_sprite"\n      svg_key?(key)\n    elsif data["hash_key"] == "category_url"')
        transport.write_text(text)
        array=self.path/'theme_array_transport.rb'
        array.write_text(array.read_text().replace('  def admitted_value?(data)\n','  def admitted_value?(data)\n    return admitted_svg_value?(data) if data["hash_key"] == "svg_sprite"\n'))
        context=self.path/'category_cache_context.rb'
        text=context.read_text().replace('        server_theme_compiler_values = {}','        server_theme_compiler_values = {}\n        server_svg_values = {}')
        text=text.replace('["category_url", "icon_manager", "scheme_hex_for_name", lease.theme_cache_key]', '["category_url", "icon_manager", "scheme_hex_for_name", "svg_sprite", lease.theme_cache_key]')
        text=text.replace('(data["marshalled"] == false || data["hash_key"] == lease.theme_cache_key)', '(data["marshalled"] == false || data["hash_key"] == lease.theme_cache_key || data["hash_key"] == "svg_sprite")')
        text=text.replace('          else\n            server_theme_compiler_values[data["key"]]', '          elsif data["hash_key"] == "svg_sprite"\n            server_svg_values[data["key"]] = lease.decoded_theme_value(data)\n          else\n            server_theme_compiler_values[data["key"]]')
        anchor='        record[:server_theme_compiler_values] = server_theme_compiler_values'
        assert anchor in text
        text=text.replace(anchor,anchor+'\n        record[:svg_cache] = svg_cache_values\n        record[:server_svg_values] = server_svg_values')
        # Preserve the original publication/defer/worker error before checking
        # its secondary cache-value divergence. Both invariants still reject.
        primary='          raise "compiler cache real server/local values differ" unless record[:theme_compiler_cache] == server_theme_compiler_values'
        assert primary in text
        text=text.replace(primary,primary+'\n          raise "SVG cache real server/local values differ" unless record[:svg_cache] == server_svg_values')
        context.write_text(text)
        highlight=self.path/'client_highlight_context.rb'
        highlight.write_text(highlight.read_text().replace('  def expected_body_events\n','  def expected_client_highlight_events\n'))
        (self.path/'emitted/runtime/svg_cache.rbs').write_text('''module CategoryCacheBootstrap
  @acquired_svg_cache: CategoryCacheApplication::DistributedCache?
  def self.svg_cache: () -> CategoryCacheApplication::DistributedCache
  def self.svg_cache_values: () -> Hash[String, untyped]
end
module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_svg_icons: (String key) { () -> Array[String?] } -> Array[String?]
    def svg_values: () -> Hash[String, untyped]
  end
end
class CategoryCacheLease
  @svg_encodings: Hash[String, String]?
  def svg_key?: (String key) -> bool
  def note_svg_icons: (String key, Array[String?] value) -> nil
end
module RequestSvgSource
  @cache: CategoryCacheApplication::DistributedCache?
  def self.cache: () -> CategoryCacheApplication::DistributedCache
  def self.path: (?Integer? id) -> String
  def self.version: (?Integer? id) -> String
  def self.bundle: (?Integer? id) -> String
  def self.all_icons: (?Integer? id) -> Array[String?]
  def self.settings_icons: () -> Array[String?]
  def self.badge_icons: () -> Array[String?]
  def self.group_icons: () -> Array[String?]
  def self.get_set_cache_version: (String key) { () -> String } -> String
  def self.get_set_cache_icons: (String key) { () -> Array[String?] } -> Array[String?]
end
module RequestSvgBootstrap
  @events: Array[String]?
  @notes: Array[String]?
  def self.bind: (Array[String] events) -> nil
  def self.notes: () -> Array[String]
  def self.note_cache: (String key, CategoryCacheApplication::DistributedCache cache) -> nil
  def self.settings_hash: () -> bot
  def self.path: (Integer? id) -> String
  def self.badge_icons: () -> Array[String?]
  def self.group_icons: () -> Array[String?]
end
''')
        entry=self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "svg_cache_transport"\nrequire_relative "svg_cache_context"\nCategoryCacheBootstrap.configure('))
        original=self.path/'client_highlight_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "svg_cache_original_context"\n')

    def verify_continuation(self):
        super().verify_continuation()
        values=[]
        for name in ('native','compat','compat-original'):
            rows=[json.loads(line.split(' ',1)[1])for line in(self.path/(name+'.stdout')).read_text().splitlines()if line.startswith('FIDELITY_HTML_STAGE ')]
            observed=[row['template_prefix']['svg_cache']for row in rows]
            assert len(observed)==2
            if self.svg_bundle_supported:
                assert all(v['registered'] and v['source_getter_returned']for v in observed)
                assert len(observed[0]['notes'])==(11 if self.client_meta_supported else 10) and len(observed[1]['notes'])==(18 if self.client_meta_supported else 16)
                assert all({'settings_icons','badge_icons','group_icons'} < set(v['values'])for v in observed)
            elif self.svg_icon_producers_supported:
                assert all(v['registered'] and v['source_getter_returned'] and set(v['values'])=={'settings_icons','badge_icons','group_icons'}for v in observed)
                assert len(observed[0]['notes'])==8 and len(observed[1]['notes'])==16
            else:
                assert all(v['registered'] and not v['values'] and not v['source_getter_returned']for v in observed)
                assert len(observed[0]['notes'])==3 and len(observed[1]['notes'])==6
            values.append(observed)
        assert values[0]==values[1]==values[2]
        self.evidence.update(actual_svg_cache_prefix=values[0],svg_getter_returned=False,svg_pg_queries_acquired=False,svg_xml_acquired=False,full_layout_completed=False)

    def command(self,name,argv,**kwargs):
        if name.startswith('compat'):
            tree=self.path/('compat-preflight'if name=='compat-preflight'else'compat')
            if tree.exists():
                for item in SVG_FILES:shutil.copyfile(self.path/item,tree/item)
        return super().command(name,argv,**kwargs)

if __name__=='__main__':
    os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:4]);execute(SvgCacheStageRun())
