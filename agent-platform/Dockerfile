# Agent platform — one container, many users.
#
# Slim rather than alpine: the wheels this depends on (pydantic-core, httpx) have manylinux builds
# that alpine's musl cannot use, so alpine would compile them from source for a smaller image that
# takes ten times longer to build.

FROM python:3.13-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependencies first, so a source-only change does not re-resolve them.
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .

# Evals ship with the image: the safety corpus is how you verify a deployed build still refuses
# what it is supposed to refuse, which is worth being able to run in place.
COPY evals ./evals

# Non-root. Nothing here needs to write to the filesystem.
RUN useradd --create-home --uid 10001 agent && chown -R agent:agent /app
USER agent

EXPOSE 8100

# One worker. The RunRegistry and the cost ledger are per-process, so two workers would each hold
# half the in-flight turns and neither would find the other's call ids (agent_server/runs.py).
# Scaling past one process needs the Postgres-backed versions first.
CMD ["uvicorn", "agent_server.api:app", "--host", "0.0.0.0", "--port", "8100", "--workers", "1"]
