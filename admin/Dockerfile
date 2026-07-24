FROM node:24-slim AS ui-builder
ARG GIT_COMMIT=unknown
ENV APP_VERSION=$GIT_COMMIT
WORKDIR /ui
RUN corepack enable
COPY ui/package.json ui/pnpm-lock.yaml ui/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY ui/ .
RUN pnpm build

FROM python:3.11-alpine
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY requirements.lock .
RUN apk upgrade --no-cache \
    && apk add --no-cache openssl \
    && pip install --no-cache-dir --require-hashes -r requirements.lock \
    && pip uninstall -y pip setuptools wheel
COPY api/ ./api/
COPY prepare-volumes.sh /prepare-volumes.sh
COPY --from=ui-builder /ui/dist ./static
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision="$GIT_COMMIT"
EXPOSE 8889
USER 10001:10001
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8889"]
