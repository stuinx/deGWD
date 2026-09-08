import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def function(path, name):
    source = (ROOT / path).read_text()
    start = re.search(r'^' + name + r'\(\)\s*\{', source, re.M)
    if not start:
        raise AssertionError('Missing function: ' + name)
    # Top-level functions are separated by at least two blank lines.
    end = re.search(r'^}\n(?=\n\n)', source[start.start():], re.M)
    return source[start.start():start.start() + end.end()]


def shell(script, cwd=None):
    return subprocess.run(['bash', '-c', script], cwd=cwd, text=True, capture_output=True)


class InstallReliability(unittest.TestCase):
    def test_failed_probe_is_not_success_text(self):
        source = (ROOT / 'client').read_text()
        probe = re.search(r'try_connect\(\) \{.*?^}', source, re.M | re.S).group()
        result = shell('curl(){ return 7; }; sleep(){ :; };\n' + probe + '\ntry_connect example.invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_successful_probe(self):
        source = (ROOT / 'client').read_text()
        probe = re.search(r'try_connect\(\) \{.*?^}', source, re.M | re.S).group()
        self.assertEqual(shell('curl(){ return 0; };\n' + probe + '\ntry_connect example.invalid').returncode, 0)

    def test_download_fallback_does_not_append_partial_body(self):
        for script in ['client', 'server']:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                stub = '''curl(){
local output= url=${!#}
while [[ $# -gt 0 ]]; do
  if [[ $1 == -o ]]; then output=$2; shift; fi
  shift
done
if [[ $url == https://raw.githubusercontent.com/* ]]; then
  printf PARTIAL >"$output"; return 56
fi
printf COMPLETE >"$output"
}
'''
                result = shell(stub + function(script, 'repoGet') + '\nrepoGet https://raw.githubusercontent.com/a/b/main/file', tmp)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'COMPLETE')

    def test_all_download_sources_fail_without_publishing_body(self):
        for script in ['client', 'server']:
            result = shell('curl(){ return 28; };\n' + function(script, 'repoGet') + '\nrepoGet https://raw.githubusercontent.com/a/b/main/file')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')

    def test_empty_runtime_checksum_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = function('client', 'fetchRuntimeResource').replace('/opt/de_GWD', tmp)
            result = shell('repoGet(){ return 0; };\n' + body + '\nfetchRuntimeResource '+tmp+'/asset https://example.invalid/asset 1')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(Path(tmp, 'asset').exists())

    def test_missing_checksum_cannot_match_missing_file(self):
        for script in ['client', 'server']:
            result = shell(function(script, 'checkSum') + '\ncheckSum /nonexistent-degwd-resource ""')
            self.assertEqual(result.stdout.strip(), 'false')

    def test_client_cf_credentials_exported_to_child_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = function('resource/client/ui-script/ui-installCER', 'installCER')
            body = body.replace('/opt/de_GWD', tmp+'/opt').replace('/etc/nginx', tmp+'/etc').replace('/var/www/ssl', tmp+'/ssl')
            stub = '''jq(){
case "$*" in
  *FORWARD.APIkey*) echo test-key;;
  *FORWARD.Email*) echo test@example.invalid;;
  *FORWARD.domain*) echo node.example.invalid;;
esac
}
sed(){ :; }; sponge(){ cat >/dev/null; }; chmod(){ :; }
acmeSetup(){ bash -c 'test "$CF_Key" = test-key && test "$CF_Email" = test@example.invalid' && echo EXPORTED; return 77; }
'''
            result = shell(stub + body + '\ninstallCER')
            self.assertIn('EXPORTED', result.stdout)
            self.assertNotIn('Generate & Deploy', result.stdout)
            self.assertNotEqual(result.returncode, 0)

    def test_server_acme_failure_propagates(self):
        body = function('server', 'makeSSL_D')
        stub = 'systemctl(){ echo active; }; acmeSetup(){ return 77; }; CFapikey=test-key; CFemail=test@example.invalid;\n'
        result = shell(stub + body + '\nmakeSSL_D')
        self.assertNotEqual(result.returncode, 0)

    def test_reset_keeps_new_certificate_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = function('resource/client/ui-script/ui-installCER', 'resetCER')
            for prefix in ['/var/www/ssl', '/etc/nginx', '/root/.acme.sh', '/tmp/now.cron']:
                body = body.replace(prefix, tmp+prefix)
            Path(tmp+'/tmp').mkdir()
            stub = 'openssl(){ printf key >de_GWD.key; printf cert >de_GWD.cer; }; crontab(){ :; }; sed(){ :; }; systemctl(){ :; };\n'
            result = shell(stub + body + '\nresetCER')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(Path(tmp+'/var/www/ssl/de_GWD.key').is_file())
            self.assertTrue(Path(tmp+'/var/www/ssl/de_GWD.cer').is_file())

    def test_install_syncs_clock_before_first_apt_update(self):
        source = (ROOT / 'client').read_text()
        start = source.index('installGWD()')
        chunk = source[start:source.index('\npreInstall', start)]
        self.assertIn('hwclock --hctosys', chunk)
        self.assertLess(chunk.index('hwclock --hctosys'), chunk.index('apt update'))

    def test_repoget_supports_custom_mirror_env(self):
        for script in ['client', 'server']:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                stub = '''curl(){
local output= url=${!#}
while [[ $# -gt 0 ]]; do
  if [[ $1 == -o ]]; then output=$2; shift; fi
  shift
done
if [[ $url == https://custom-mirror.example.invalid/* ]]; then
  printf CUSTOM_OK >"$output"; return 0
fi
return 28
}
'''
                result = shell(stub + 'export DE_GWD_GH_MIRROR=https://custom-mirror.example.invalid\n' + function(script, 'repoGet') + '\nrepoGet https://raw.githubusercontent.com/a/b/main/file', tmp)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'CUSTOM_OK')

    def test_runtime_sources_are_not_tied_to_upstream_de_gwd(self):
        for path in ['client', 'server', 'README.md', 'version.php']:
            self.assertNotIn('jacyl4/de_GWD', (ROOT / path).read_text())

    def test_repair_ref_is_shared_by_both_installers(self):
        for path in ['client', 'server']:
            source = (ROOT / path).read_text()
            self.assertIn('DE_GWD_REF', source)
            self.assertIn('codex/upstream-dual-repair', source)
            self.assertIn('/opt/de_GWD/.repo/repo.env', source)

    def test_checksum_metadata_accepts_hash_and_filename(self):
        for path in ['client', 'server']:
            source = (ROOT / path).read_text()
            self.assertIn('${sha256sum_nginx%%[[:space:]]*}', source)
            self.assertIn('${sha256sum_nginxConf%%[[:space:]]*}', source)

    def test_client_has_dependency_and_dns_fallbacks(self):
        source = (ROOT / 'client').read_text()
        self.assertIn('https://mirrors.aliyun.com/docker-ce/linux/debian/gpg', source)
        self.assertIn('for dnsServer in 1.1.1.1 8.8.8.8 114.114.114.114 223.5.5.5', source)

    def test_client_persists_tproxy_policy_route(self):
        source = (ROOT / 'client').read_text()
        self.assertIn('/opt/de_GWD/nftables/tproxy_route.sh', source)
        self.assertIn('ip route replace local default dev lo scope host table 220', source)
        self.assertIn('ip rule add fwmark 0x9 table 220 prio 100', source)
        self.assertIn('fwmark 0x9.*lookup 220', source)
        self.assertIn('Wants=network-online.target', source)
        self.assertIn('After=network-online.target', source)

    def test_server_fetches_repository_before_enabling_nftables(self):
        source = (ROOT / 'server').read_text()
        start = source.index('installGWD(){')
        install = source[start:source.index('\nupdateGWD(){', start)]
        self.assertLess(install.index('repoDL || exit 1'), install.index('installNftables || exit 1'))

    def test_runtime_update_scripts_use_atomic_repo_helper(self):
        for path in ['resource/client/ui-script/ui_4am', 'resource/client/ui-script/ui-autoUpdateHour']:
            source = (ROOT / path).read_text()
            self.assertIn('/opt/de_GWD/repoGet', source)
            self.assertIn('mktemp', source)

    def test_version_php_is_local(self):
        source = (ROOT / 'version.php').read_text()
        self.assertNotIn('file_get_contents(', source)

    def test_packaged_ui_matches_source(self):
        import zipfile
        with zipfile.ZipFile(ROOT/'resource/client/Archive.zip') as archive:
            for name in ['ui-installCER', 'ui-NodeOne', 'ui_4am', 'ui-autoUpdateHour']:
                self.assertEqual(archive.read('ui-script/'+name), (ROOT/'resource/client/ui-script'/name).read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
