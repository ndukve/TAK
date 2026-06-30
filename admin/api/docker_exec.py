import asyncio
import docker
from docker.errors import DockerException

CONTAINER_NAME = "takserver_config"
_client = docker.from_env()


async def run_in_container(
    cmd: list[str],
    env: dict[str, str] | None = None,
    workdir: str | None = None,
) -> tuple[int, str]:
    """
    Run cmd in CONTAINER_NAME via docker exec.
    Returns (exit_code, combined_output).
    Scoped strictly to CONTAINER_NAME — no other container can be targeted.
    Pass env vars via `env` dict instead of shell interpolation to prevent injection.
    """
    loop = asyncio.get_running_loop()

    def _exec():
        try:
            container = _client.containers.get(CONTAINER_NAME)
            result = container.exec_run(cmd, demux=False, environment=env, workdir=workdir)
            output = result.output.decode("utf-8", errors="replace") if result.output else ""
            return result.exit_code, output
        except DockerException as e:
            return 1, str(e)

    return await loop.run_in_executor(None, _exec)
