.PHONY: up down restart build update logs logs-fts logs-ui status \
        add-user list-packages serve-packages shell

ENV_FILE  := .env
DATA_DIR  := $(shell grep '^DATA_DIR=' $(ENV_FILE) 2>/dev/null | cut -d= -f2 || echo /opt/fts)
PKG_DIR   := $(DATA_DIR)/certs/clientPackages

# ── Lifecycle ─────────────────────────────────────────────────────────────────

build:
	docker compose --env-file $(ENV_FILE) build

## Pull latest config from git and rebuild the container.
update:
	@chmod +x ./update.sh && ./update.sh

up:
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	docker compose --env-file $(ENV_FILE) up -d

down:
	docker compose --env-file $(ENV_FILE) down

restart:
	docker compose --env-file $(ENV_FILE) restart

# ── User cert & package management ───────────────────────────────────────────

## Generate a TAK data package for a new user.
## Usage: make add-user USERNAME=alice
add-user:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make add-user USERNAME=alice"; exit 1; }
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	@chmod +x ./generate_user.sh
	./generate_user.sh $(USERNAME)

## List generated packages ready for distribution.
list-packages:
	@ls -lh $(PKG_DIR)/*.zip 2>/dev/null \
		|| echo "No packages yet. Run: make add-user USERNAME=alice"

## Serve packages over HTTP with correct MIME types for iOS (.p12 files).
## Download URL is printed on start. Press Ctrl+C to stop.
serve-packages:
	@[ -d "$(PKG_DIR)" ] || { echo "No packages dir at $(PKG_DIR). Run add-user first."; exit 1; }
	@FTS_IP=$$(grep '^FTS_IP=' $(ENV_FILE) | cut -d= -f2); \
	echo ""; \
	echo "  Serving packages at http://$$FTS_IP:8888/"; \
	echo "  On iPhone (Safari): http://$$FTS_IP:8888/<username>.zip"; \
	echo "  Import in iTAK: Settings → Network → Servers → + → Upload Server Package"; \
	echo "  Press Ctrl+C to stop."; \
	echo ""
	cd $(PKG_DIR) && python3 $(CURDIR)/scripts/serve_packages.py

# ── Observability ─────────────────────────────────────────────────────────────

logs:
	docker compose --env-file $(ENV_FILE) logs -f

## Stream logs for FTS core only (filters by supervisor process label)
logs-fts:
	docker exec freetakserver supervisorctl tail -f fts

## Stream logs for FTS UI only (filters by supervisor process label)
logs-ui:
	docker exec freetakserver supervisorctl tail -f fts-ui

status:
	@echo "=== Container ==="
	@docker compose --env-file $(ENV_FILE) ps
	@echo ""
	@echo "=== Supervisor processes ==="
	@docker exec freetakserver supervisorctl status 2>/dev/null || true
	@echo ""
	@echo "=== Listening ports ==="
	@ss -tlnp 2>/dev/null \
		| grep -E ":8087|:8089|:8080|:8443|:9000|:19023|:5000" \
		| awk '{print "  " $$4}' | sort -u || true
	@echo ""
	@echo "=== Tailscale ==="
	@tailscale ip -4 2>/dev/null | xargs -I{} echo "  {}" || echo "  (tailscale not found)"

# ── Debug shell ───────────────────────────────────────────────────────────────

shell:
	docker exec -it freetakserver /bin/bash
