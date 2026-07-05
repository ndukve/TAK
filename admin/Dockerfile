# Pulled through the local registry mirror (see docker-compose.yml's
# `registry` service), pinned by exact digest for reproducible builds.
FROM localhost:5000/library/node@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0 AS ui-builder
WORKDIR /ui
RUN npm install -g pnpm
COPY ui/package.json ./
RUN pnpm install
COPY ui/ .
RUN pnpm build

FROM localhost:5000/library/python@sha256:b27df5841f3355e9473f9a516d38a6783b6c8dfeacaf2d14a240f443b368ddb6
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api/ ./api/
COPY --from=ui-builder /ui/dist ./static
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.revision="$GIT_COMMIT"
EXPOSE 8889
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8889"]
