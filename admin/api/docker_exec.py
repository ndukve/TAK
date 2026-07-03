import asyncio
import re
import docker
from docker.errors import DockerException

SERVICE_NAME = "takserver_config"
_client = docker.from_env()

_ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')


def _strip_ansi(text: str) -> str:
    """Container scripts print colored output for terminal use; strip escape
    codes before this reaches a web UI toast/error message."""
    return _ANSI_RE.sub("", text)


def _get_takserver_config():
    """Find takserver_config container by compose service label (works with any project prefix)."""
    matches = _client.containers.list(
        filters={"label": f"com.docker.compose.service={SERVICE_NAME}"}
    )
    if not matches:
        raise DockerException(f"No running container for service '{SERVICE_NAME}'")
    return matches[0]


async def run_in_container(
    cmd: list[str],
    env: dict[str, str] | None = None,
    workdir: str | None = None,
) -> tuple[int, str]:
    loop = asyncio.get_running_loop()

    def _exec():
        try:
            container = _get_takserver_config()
            # Cert files are root-owned; without an explicit user the exec
            # can silently fail to remove/read them depending on the image's
            # default exec user.
            result = container.exec_run(cmd, demux=False, environment=env, workdir=workdir, user="root")
            output = result.output.decode("utf-8", errors="replace") if result.output else ""
            return result.exit_code, _strip_ansi(output)
        except DockerException as e:
            return 1, str(e)

    return await loop.run_in_executor(None, _exec)
