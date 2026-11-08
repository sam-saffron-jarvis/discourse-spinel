#!/usr/bin/env python3
"""Concrete Theme bulk cache capability on existing guarded Scheduler/MessageBus."""
import json
import os
import shutil
from probe_client_overrides_stage import ClientOverrideStageRun
from verify import HERE, ROOT

BULK_FILES = ('theme_bulk_cache_source.rb', 'theme_bulk_transport.rb', 'theme_bulk_original_context.rb')

class ThemeBulkCapabilityRun(ClientOverrideStageRun):
    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command('generate-theme-bulk-capability', ['bundle', 'exec', 'ruby', HERE/'tools/generate_theme_bulk_capability.rb', self.path], cwd=ROOT/'discourse')
        self.evidence['theme_bulk_source'] = json.loads((self.path/'theme-bulk-source-proof.json').read_text())

    def generate(self):
        super().generate()
        for name in BULK_FILES:
            file = HERE/'test'/name
            if file.exists(): shutil.copyfile(file, self.path/name)
        (self.path/'emitted/runtime/theme_bulk.rbs').write_text('''module CategoryCacheApplication
  class DistributedCache
    def defer_get_set_fields: (Array[Array[Integer | Symbol]] keys, ^(Array[Integer | Symbol]) -> String key_block) { (Array[Array[Integer | Symbol]]) -> Array[Array[String]?] } -> Hash[Array[Integer | Symbol], Array[String]?]
    def theme_field_hit: (String key) -> Array[String]?
    def theme_field_present?: (String key) -> bool
  end
end
class CategoryCacheLease
  @theme_field_encodings: Hash[String, String?]?
  @field_bulk_jobs: Integer?
  @field_bulk_members: Integer?
  def theme_field_key?: (String key) -> bool
  def note_theme_field_value: (String key, Array[String]? value) -> nil
  def note_bulk_enqueue: (Integer count) -> nil
  def field_bulk_jobs: () -> Integer
  def field_bulk_members: () -> Integer
end
''')
        transport = self.path/'category_cache_transport.rb'
        text = transport.read_text()
        text = text.replace('data["value"].is_a?(String)', '(data["value"].is_a?(String) || admitted_field_value?(data))')
        text = text.replace('key == "compiler_version" || ', 'key == "compiler_version" || theme_field_key?(key) || ')
        text = text.replace('key == CategoryCacheBootstrap.lease.theme_cache_key + "_set"', '(key == CategoryCacheBootstrap.lease.theme_cache_key + "_set" || key == CategoryCacheBootstrap.lease.theme_cache_key + "_bulk_set")')
        transport.write_text(text)
        context = self.path/'category_cache_context.rb'
        text = context.read_text()
        anchor = 'hit = value.is_a?(Array) ? acquired_theme_compiler_cache.defer_get_set_assets(key)'
        assert text.count(anchor) == 1
        text = text.replace(anchor, 'hit = lease.theme_field_key?(key) ? acquired_theme_compiler_cache.theme_field_hit(key) : value.is_a?(Array) ? acquired_theme_compiler_cache.defer_get_set_assets(key)')
        text = text.replace('record[:queued] == record[:publications] && rows.size == record[:publications]', 'record[:queued] - lease.field_bulk_jobs + lease.field_bulk_members == record[:publications] && rows.size == record[:publications]')
        text = text.replace('record[:publications] = lease.publication_count', 'record[:publications] = lease.publication_count\n        record[:expected_publications] = record[:queued] - lease.field_bulk_jobs + lease.field_bulk_members\n        record[:field_bulk_jobs] = lease.field_bulk_jobs\n        record[:field_bulk_members] = lease.field_bulk_members')
        context.write_text(text)
        array = self.path/'theme_array_transport.rb'
        text = array.read_text().replace('  def admitted_value?(data)\n', '  def admitted_value?(data)\n    key = data["key"]\n    return admitted_field_value?(data) if key.is_a?(String) && theme_field_key?(key)\n').replace('raise "unowned encoded Theme value" unless admitted_value?(data)', 'raise "unowned encoded Theme value" unless admitted_value?(data) || admitted_field_value?(data)')
        array.write_text(text)
        entry = self.path/'entry.rb'
        entry.write_text(entry.read_text().replace('\nCategoryCacheBootstrap.configure(', '\nrequire_relative "theme_bulk_transport"\nrequire_relative "theme_bulk_cache_source"\nCategoryCacheBootstrap.configure('))
        original = self.path/'client_override_original_context.rb'
        original.write_text(original.read_text()+'\nrequire_relative "theme_bulk_original_context"\n')

    def command(self, name, argv, **kwargs):
        if name.startswith('compat'):
            tree = self.path/('compat-preflight' if name == 'compat-preflight' else 'compat')
            if tree.exists():
                for item in BULK_FILES: shutil.copyfile(self.path/item, tree/item)
        return super().command(name, argv, **kwargs)
