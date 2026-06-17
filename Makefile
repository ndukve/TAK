.PHONY: build up down restart update logs logs-db status shell \
        add-user list-packages serve-packages

ENV_FILE := takserver.env

# ── Lifecycle ─────────────────────────────────────────────────────────────────

build:
	docker compose --env-file $(ENV_FILE) build

up:
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	docker compose --env-file $(ENV_FILE) up -d

down:
	docker compose --env-file $(ENV_FILE) down

restart:
	docker compose --env-file $(ENV_FILE) restart

update:
	@chmod +x ./update.sh && ./update.sh

# ── User management ───────────────────────────────────────────────────────────

## Generate a TAK data package for a new user.
## Usage: make add-user USERNAME=alice
add-user:
	@[ -n "$(USERNAME)" ] || { echo "Usage: make add-user USERNAME=alice"; exit 1; }
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	@chmod +x ./generate_user.sh
	./generate_user.sh $(USERNAME)

## List generated packages ready for distribution.
list-packages:
	@docker exec takserver_config ls -lh /opt/tak/data/certs/files/clientpkgs/ 2>/dev/null \
		|| echo "No packages yet. Run: make add-user USERNAME=alice"

## Serve packages over HTTP on port 8888 (pkg_server container handles this automatically).
serve-packages:
	@TAK_ADDR=$$(grep '^TAK_SERVER_ADDRESS=' $(ENV_FILE) | cut -d= -f2); \
	echo ""; \
	echo "  Package server running at http://$$TAK_ADDR:8888/"; \
	echo "  On device: http://$$TAK_ADDR:8888/<username>.zip"; \
	echo ""

# ── Observability ─────────────────────────────────────────────────────────────

logs:
	docker compose --env-file $(ENV_FILE) logs -f

logs-db:
	docker compose --env-file $(ENV_FILE) logs -f takdb

status:
	@echo "=== Services ==="
	@docker compose --env-file $(ENV_FILE) ps
	@echo ""
	@echo "=== Listening ports ==="
	@ss -tlnp 2>/dev/null \
		| grep -E ":8089|:8443|:8888" \
		| awk '{print "  " $$4}' | sort -u || true

# ── Debug shell ───────────────────────────────────────────────────────────────

shell:
	docker exec -it takserver_config /bin/bash
