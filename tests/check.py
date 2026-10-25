"""Exercise the actual installer patch block without installing any services."""
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
installer = (root / 'install.sh').read_text(encoding='utf-8')
ref = installer.split('UPSTREAM_REF=', 1)[1].splitlines()[0]
subprocess.run([os.environ.get('TEST_BASH', 'bash'), '-n', str(root / 'install.sh')], check=True)
subprocess.run([os.environ.get('TEST_SH', 'sh'), str(root / 'install.sh'), '--help'], check=True)
for args in [[], ['--mode', 'wrong'], ['--mode', 'temp', '--transport', 'wrong']]:
    assert subprocess.run([os.environ.get('TEST_SH', 'sh'), str(root / 'install.sh'), *args], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 2
with tempfile.TemporaryDirectory() as directory:
    work = pathlib.Path(directory)
    if len(sys.argv) > 1:
        upstream = pathlib.Path(sys.argv[1]).read_bytes()
    else:
        upstream = urllib.request.urlopen(
            f'https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/{ref}/singbox.sh', timeout=60).read()
    (work / 'upstream.sh').write_bytes(upstream)
    # Include call-site guards and sed commands verbatim from the installer.
    block = installer.split('# Fail closed', 1)[1].split('stamp=$(date', 1)[0]
    block = '# Fail closed' + block
    script = 'set -eu\nwork=$1\n' + block
    (work / 'check.sh').write_text(script, encoding='utf-8', newline='\n')
    subprocess.run([os.environ.get('TEST_BASH', 'bash'), str(work / 'check.sh'), str(work)], check=True)
    result = (work / 'manager.sh').read_text(encoding='utf-8')
    assert result.count('--protocol "${ARGO_TRANSPORT_PROTOCOL}"') == 2
    assert '--protocol http2' not in result
    assert '    _argo_auto_entry\n' in result
    assert 'temp) tunnel_mode=1;; fixed) tunnel_mode=2;;' in result
    assert 'Reinstall from zhangx16/Argo-Script' in result
    assert "pgrep -x 'cron|crond|cronie'" in result
    assert 'pidof cron crond cronie' in result
    assert '_enable_argo_watchdog || { _stop_argo_tunnel "$target_port"; return 1; }' in result
    rollback = result.split('if ! _add_node_to_yaml "$proxy_json"; then', 1)[1].split('    fi', 1)[0]
    assert '_manage_service "restart"' in rollback
    # Test the persistent setting validation independently from upstream's main.
    extension = installer.split("cat > \"$work/extension\" <<'EOF'\n", 1)[1].split('\nEOF', 1)[0]
    settings = work / 'transport'
    extension = extension.replace('/usr/local/etc/sing-box/argo-transport', settings.as_posix())
    for value in ['auto', 'http2', 'quic', 'invalid']:
        settings.write_text(value + '\n', encoding='utf-8', newline='\n')
        process = subprocess.run([os.environ.get('TEST_BASH', 'bash'), '-c', extension + '\nprintf "%s" "$ARGO_TRANSPORT_PROTOCOL"'],
                                 capture_output=True, text=True)
        assert process.returncode == (2 if value == 'invalid' else 0)
        if value != 'invalid':
            assert process.stdout == value
print('PASS: syntax, CLI validation, actual patch, transport persistence and validation')



