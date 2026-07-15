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


async def run_in_container(
    cmd: list[str],
    env: dict[str, str] | None = None,
    workdir: str | None = None,
) -> tuple[int, str]:
    loop = asyncio.get_running_loop()

    def _exec():
        try:
            # Cert files are root-owned; without an explicit user the exec
            # can silently fail to remove/read them depending on the image's
            # default exec user. Always use the fixed name: the socket proxy
            # rejects exec creation by ID or any other container name.
            exec_data = _client.api.exec_create(
                SERVICE_NAME,
                cmd,
                stdout=True,
                stderr=True,
                environment=env,
                workdir=workdir,
                user="root",
            )
            output_bytes = _client.api.exec_start(exec_data["Id"], demux=False)
            inspected = _client.api.exec_inspect(exec_data["Id"])
            output = output_bytes.decode("utf-8", errors="replace") if output_bytes else ""
            return inspected.get("ExitCode", 1), _strip_ansi(output)
        except DockerException as e:
            return 1, str(e)

    return await loop.run_in_executor(None, _exec)
