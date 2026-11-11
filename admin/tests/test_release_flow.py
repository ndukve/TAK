"""scripts/_release.sh: choosing and applying the version update.sh moves to, in scratch repositories."""

import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIB = ROOT / "scripts" / "_release.sh"


def sh(cwd, script):
    return subprocess.run(["bash", "-c", f". {LIB}\nset -e\n{script}"], cwd=cwd, text=True, capture_output=True)


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=cwd, text=True, capture_output=True, check=True).stdout.strip()


@pytest.fixture
def repos(tmp_path):
    origin, work = tmp_path / "origin.git", tmp_path / "work"
    git(tmp_path, "init", "-q", "--bare", "-b", "main", str(origin))
    git(tmp_path, "clone", "-q", str(origin), str(work))
    for n in (1, 2, 3):
        (work / "f").write_text(str(n))
        git(work, "add", "f")
        git(work, "commit", "-q", "-m", f"c{n}")
        if n == 2:
            git(work, "tag", "-a", "v0.2.0", "-m", "v0.2.0")
    git(work, "push", "-q", "origin", "main", "--tags")
    return work


def test_default_target_is_the_upstream_tip_and_a_tag_and_describe(repos):
    git(repos, "reset", "-q", "--hard", "v0.2.0")
    tip = git(repos, "rev-parse", "origin/main")
    assert sh(repos, 'release_target origin/main "" 0 /nope').stdout.strip() == tip
    assert sh(repos, 'release_target origin/main v0.2.0 0 /nope').stdout.strip() == git(repos, "rev-parse", "v0.2.0^{commit}")
    assert sh(repos, "release_describe").stdout.strip() == "v0.2.0"
    assert "no tag 'v9'" in sh(repos, 'release_target origin/main v9 0 /nope').stderr


def test_move_forward_then_back_and_remember(repos):
    git(repos, "reset", "-q", "--hard", "v0.2.0")
    old = git(repos, "rev-parse", "HEAD")
    tip = git(repos, "rev-parse", "origin/main")
    out = sh(repos, f'release_apply {tip}; release_remember {old} prev; release_target origin/main "" 1 prev')
    assert out.returncode == 0 and out.stdout.strip() == old and git(repos, "rev-parse", "HEAD") == tip
    assert sh(repos, f"release_apply {old}").returncode == 0 and git(repos, "rev-parse", "HEAD") == old     # back to the older version
    assert "no earlier version" in sh(repos, 'release_target origin/main "" 1 missing-file').stderr


def test_moving_back_is_refused_when_local_commits_exist_on_no_remote(repos):
    (repos / "f").write_text("local")
    git(repos, "commit", "-q", "-am", "local only")
    result = sh(repos, f"release_apply {git(repos, 'rev-parse', 'v0.2.0^{commit}')}")
    assert result.returncode == 1 and "exist on no remote" in result.stderr


@pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen needed for signed tags")
def test_an_unsigned_tag_is_refused_when_a_signers_file_is_given(repos, tmp_path):
    key = tmp_path / "k"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
    signers = tmp_path / "allowed_signers"
    signers.write_text("t@t " + (tmp_path / "k.pub").read_text())
    git(repos, "config", "gpg.format", "ssh")
    git(repos, "config", "user.signingkey", str(key))
    git(repos, "config", "gpg.ssh.allowedSignersFile", str(signers))
    git(repos, "tag", "-s", "-m", "signed", "v0.3.0")
    assert sh(repos, f'release_target origin/main v0.3.0 0 /nope {signers}').returncode == 0
    refused = sh(repos, f'release_target origin/main v0.2.0 0 /nope {signers}')
    assert refused.returncode == 1 and "not signed" in refused.stderr
