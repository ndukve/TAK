.PHONY: build up down restart update logs logs-db status shell \
        add-user list-packages serve-packages install-plugin add-service \
        add-plugin list-plugins

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
	@docker compose --env-file $(ENV_FILE) exec takserver_config ls -lh /opt/tak/data/certs/files/clientpkgs/ 2>/dev/null \
		|| echo "No packages yet. Run: make add-user USERNAME=alice"

## Serve packages and plugins over HTTP on port 8888 (pkg_server handles this automatically).
serve-packages:
	@TAK_ADDR=$$(grep '^TAK_SERVER_ADDRESS=' $(ENV_FILE) | cut -d= -f2); \
	echo ""; \
	echo "  Package server running at http://$$TAK_ADDR:8888/"; \
	echo "  User packages : http://$$TAK_ADDR:8888/<username>.zip"; \
	echo "  Plugin repo   : http://$$TAK_ADDR:8888/plugins/"; \
	echo ""

## Upload a client plugin APK to the on-server plugin repository.
## Usage: make add-plugin APK=/path/to/plugin.apk
add-plugin:
	@[ -n "$(APK)" ] || { echo "Usage: make add-plugin APK=/path/to/plugin.apk"; exit 1; }
	@[ -f $(ENV_FILE) ] || { echo "Run './install.sh' first"; exit 1; }
	@docker compose --env-file $(ENV_FILE) exec takserver_config mkdir -p /opt/tak/data/plugins
	docker compose --env-file $(ENV_FILE) cp $(APK) takserver_config:/opt/tak/data/plugins/
	@TAK_ADDR=$$(grep '^TAK_SERVER_ADDRESS=' $(ENV_FILE) | cut -d= -f2); \
	echo "Plugin available: http://$$TAK_ADDR:8888/plugins/$(notdir $(APK))"

## List client plugins uploaded to the server.
list-plugins:
	@docker compose --env-file $(ENV_FILE) exec takserver_config \
		ls -lh /opt/tak/data/plugins/ 2>/dev/null \
		|| echo "No plugins yet. Run: make add-plugin APK=/path/to/plugin.apk"

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

# ── Plugin management ─────────────────────────────────────────────────────────

## Install a plugin JAR. Usage: make install-plugin JAR=/path/to/plugin.jar
install-plugin:
	@[ -n "$(JAR)" ] || { echo "Usage: make install-plugin JAR=/path/to/plugin.jar"; exit 1; }
	docker compose --env-file $(ENV_FILE) cp $(JAR) takserver_pluginmanager:/opt/tak/plugins/
	docker compose --env-file $(ENV_FILE) restart takserver_pluginmanager
	@echo "Plugin installed: $(notdir $(JAR))"

## Generate PEM cert+key for a machine service (e.g. EFDI moon-pod).
## Usage: make add-service NAME=efdi-pod
add-service:
	@[ -n "$(NAME)" ] || { echo "Usage: make add-service NAME=efdi-pod"; exit 1; }
	@chmod +x ./scripts/generate_service_cert.sh
	./scripts/generate_service_cert.sh $(NAME)

# ── Debug shell ───────────────────────────────────────────────────────────────

shell:
	docker compose --env-file $(ENV_FILE) exec takserver_config /bin/bash
