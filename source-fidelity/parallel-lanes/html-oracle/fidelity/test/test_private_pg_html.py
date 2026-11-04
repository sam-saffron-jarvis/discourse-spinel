import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('private_pg_html', HERE/'tools/private_pg_html.py')
pg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pg)

class PrivatePGSafetyTests(unittest.TestCase):
    def test_zombie_missing_and_reused_process_ids_are_not_live_server(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'42').mkdir()
            fields=['S']+['0']*18+['123']+['0']*5
            stat=root/'42/stat';stat.write_text('42 (postgres with spaces) '+ ' '.join(fields))
            self.assertTrue(pg.live_owned_process(42,'123',root))
            self.assertFalse(pg.live_owned_process(42,'456',root))
            fields[0]='Z';stat.write_text('42 (postgres) '+ ' '.join(fields))
            self.assertFalse(pg.live_owned_process(42,'123',root))
            stat.unlink();self.assertFalse(pg.live_owned_process(42,'123',root))

    def test_no_fixture_or_commands_without_exact_authorization(self):
        with tempfile.TemporaryDirectory() as d:
            auth=Path(d)/'auth.json';auth.write_text(json.dumps({'selected_option':'Keep every DB read-only'}))
            base=Path(d)/'fixture'
            with patch.object(pg,'AUTH',auth), patch.object(pg,'checked',side_effect=AssertionError('must not execute')):
                with self.assertRaisesRegex(RuntimeError,'authorization'):
                    pg.PrivatePG(base).__enter__()
            self.assertFalse(base.exists())

    def test_snapshot_uses_forced_readonly_and_failed_setup_removes_raw_dump(self):
        with tempfile.TemporaryDirectory() as d:
            base=Path(d)/'fixture'; calls=[]
            def command(argv,*,env,log,timeout=180):
                calls.append((argv,env.copy()))
                if argv[0]=='psql':return 'discourse_development|5499|on'
                if argv[0]=='pg_dump':
                    Path(argv[argv.index('--file')+1]).write_bytes(b'private test snapshot')
                    return ''
                raise RuntimeError('test init failure')
            with patch.object(pg,'checked',command):
                with self.assertRaisesRegex(RuntimeError,'init failure'):
                    pg.PrivatePG(base).__enter__()
            self.assertFalse((base/'snapshot.dump').exists())
            dump_env=next(e for a,e in calls if a[0]=='pg_dump')
            self.assertEqual(dump_env['PGPORT'],'5499')
            self.assertIn('default_transaction_read_only=on',dump_env['PGOPTIONS'])
            self.assertNotIn('off',dump_env['PGOPTIONS'])
            self.assertTrue(json.loads((base/'private-pg-evidence.json').read_text())['cleanup_verified'])

    def ruby_guard(self, manifest):
        env=os.environ.copy();env['FIDELITY_PRIVATE_PG_MANIFEST']=str(manifest)
        program='''module FidelityOracleIsolation; class UnsafeEndpoint < SecurityError; end; end
require ARGV.fetch(0)
begin
 FidelityPrivatePG.manifest!
 abort "unproven manifest accepted"
rescue FidelityOracleIsolation::UnsafeEndpoint
 puts "rejected"
end
'''
        return subprocess.run(['ruby','-e',program,str(HERE/'tools/private_pg_oracle_guard.rb')],
                              env=env,text=True,capture_output=True)

    def test_missing_manifest_fails_closed_before_any_pg_constructor(self):
        p=self.ruby_guard('/tmp/nonexistent-owned-pg-manifest-test.json')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(p.stdout.strip(),'rejected')

    def test_shared_port_is_rejected_even_with_real_authorization_hash(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'manifest.json';p.write_text(json.dumps({
                'kind':'owned_disposable_html_oracle_pg','schema':1,
                'authorization_path':str(pg.AUTH),'authorization_sha256':pg.digest(pg.AUTH),
                'port':5499}))
            p.chmod(0o600)
            result=self.ruby_guard(p)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.strip(),'rejected')

    def test_untrusted_manifest_permissions_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'manifest.json';p.write_text('{}');p.chmod(0o644)
            result=self.ruby_guard(p)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.strip(),'rejected')

if __name__=='__main__':unittest.main()
