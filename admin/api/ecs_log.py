"""Shared ECS-compatible ndJSON logging (pvarki best-practices' logging.md:
"All applications MUST output their logs in ECS-compatible ndJSON format by
default", with an env var escape hatch for local development).

Same module as the sibling EFDI project's compose/control/ecs_log.py — kept
in sync manually. Not yet wired anywhere: this app currently has no
application-level logging at all (only uvicorn's own default access logs),
so there's no existing print()/logging call site to convert as a pilot the
way EFDI's video_zenoh_bridge.py was. Import this the next time a module
here needs to log something of its own.

Usage:
    from .ecs_log import get_logger
    log = get_logger("replay")
    log.info("recording started", extra={"service": service})

Format (env):
    EFDI_LOG_FORMAT=ndjson   # default — one ECS-shaped JSON object per line
    EFDI_LOG_FORMAT=text     # human-readable for local dev
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import sys

_ECS_VERSION = "8.11.0"


class _ECSFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        doc = {
            "@timestamp": datetime.datetime.fromtimestamp(
                record.created, tz=datetime.timezone.utc
            ).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
            "ecs.version": _ECS_VERSION,
            "log.level": record.levelname.lower(),
            "log.logger": record.name,
            "message": record.getMessage(),
            "service.name": record.name,
        }
        if record.exc_info:
            doc["error.stack_trace"] = self.formatException(record.exc_info)
        reserved = logging.LogRecord(
            "", 0, "", 0, "", (), None
        ).__dict__.keys()
        for key, value in record.__dict__.items():
            if key not in reserved and key not in doc:
                doc[key] = value
        return json.dumps(doc, default=str, separators=(",", ":"))


def get_logger(service_name: str) -> logging.Logger:
    """One configured logger per service, ndJSON to stdout by default.

    Idempotent — calling this twice for the same service_name returns the
    same logger without adding a second handler."""
    logger = logging.getLogger(service_name)
    if logger.handlers:
        return logger
    handler = logging.StreamHandler(sys.stdout)
    if os.environ.get("EFDI_LOG_FORMAT", "ndjson").strip().lower() == "text":
        handler.setFormatter(logging.Formatter(
            "%(asctime)s %(name)s %(levelname)s: %(message)s"
        ))
    else:
        handler.setFormatter(_ECSFormatter())
    logger.addHandler(handler)
    logger.setLevel(os.environ.get("EFDI_LOG_LEVEL", "INFO").strip().upper())
    logger.propagate = False
    return logger
