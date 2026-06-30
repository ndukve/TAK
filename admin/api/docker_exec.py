import asyncio
import docker
from docker.errors import DockerException

SERVICE_NAME = "takserver_config"
_client = docker.from_env()


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
            result = container.exec_run(cmd, demux=False, environment=env, workdir=workdir)
            output = result.output.decode("utf-8", errors="replace") if result.output else ""
            return result.exit_code, output
        except DockerException as e:
            return 1, str(e)

    return await loop.run_in_executor(None, _exec)
