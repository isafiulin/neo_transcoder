#!/usr/bin/env python3
"""Offline check: a failed Git build must never reach installation."""
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name('deploy-git.sh').resolve()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    repo, tools = root / 'repo', root / 'tools'
    repo.mkdir()
    tools.mkdir()
    (repo / 'ui').mkdir()
    (repo / 'ui/.keep').touch()
    (repo / 'scripts').mkdir()

    def executable(path, body):
        path.write_text('#!/bin/sh\nset -eu\n' + body)
        path.chmod(0o755)

    executable(tools / 'uname', 'echo Linux\n')
    executable(tools / 'id', 'echo 1000\n')
    executable(tools / 'go', '[ "${FAIL_BUILD:-0}" = 0 ]\n')
    for name in ('flutter', 'pkg-config', 'cc'):
        executable(tools / name, 'exit 0\n')
    executable(tools / 'sudo', 'echo install >> "$DEPLOY_TRACE"\n')
    executable(repo / 'scripts/build-release.sh', '''mkdir -p "$OUT"
for name in neotranscoder neotranscoder-srt-worker install.sh update.sh; do
 printf '#!/bin/sh\nexit 0\n' > "$OUT/$name"
 chmod +x "$OUT/$name"
done
''')
    def git(*args):
        subprocess.run(['git', '-C', str(repo), *args], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    git('init')
    git('add', '.')
    git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
        'commit', '-m', 'deploy fixture')
    git('tag', 'test-release')
    trace = root / 'install.log'
    env = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'],
               DEPLOY_TRACE=str(trace), TMPDIR=str(root))
    for ref, fail, expected in [('test-release', '1', False),
                                ('missing-ref', '0', False),
                                ('test-release', '0', True)]:
        result = subprocess.run(['sh', str(script), str(repo), ref],
                                env=dict(env, FAIL_BUILD=fail),
                                capture_output=True, text=True)
        assert (result.returncode == 0) == expected, result.stderr
        assert trace.exists() == expected, 'failed build reached installation'
        assert not list(root.glob('tmp.*')), 'temporary checkout leaked'
    assert trace.read_text().splitlines() == ['install']
print('Git deployment checks passed')
