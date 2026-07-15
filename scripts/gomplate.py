#!/usr/bin/env python3
"""Render the small, deliberately supported template subset used by TAK.

This replaces the large third-party gomplate binary.  Supporting only the
expressions present in this repository keeps the runtime dependency surface
small and makes unknown template syntax fail closed instead of being silently
copied into a live TAK configuration.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import unicodedata
from pathlib import Path


ENV_NAME = r"[A-Za-z_][A-Za-z0-9_]*"


def _value(name: str, default: str = "") -> str:
    return os.environ.get(name) or default


def _slug(value: str) -> str:
    value = value.replace("&", " and ")
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def render(template: str) -> str:
    conditional = re.compile(
        rf'{{{{\s*if\s+getenv\s+"({ENV_NAME})"\s+"([^"]*)"\s*}}}}'
        r"(.*?)"
        r"{{\s*else\s*}}"
        r"(.*?)"
        r"{{\s*end\s*}}",
        re.DOTALL,
    )

    while match := conditional.search(template):
        replacement = match.group(3) if _value(match.group(1), match.group(2)) else match.group(4)
        template = template[: match.start()] + replacement + template[match.end() :]

    slugged_default = re.compile(
        rf'{{{{\s*\(\s*\.Env\.({ENV_NAME})\s*\|\s*default\s+"([^"]*)"\s*\)'
        r"\s*\|\s*strings\.Slug\s*\}\}"
    )
    template = slugged_default.sub(lambda m: _slug(_value(m.group(1), m.group(2))), template)

    with_default = re.compile(
        rf'{{{{\s*\.Env\.({ENV_NAME})\s*\|\s*default\s+"([^"]*)"\s*}}}}'
    )
    template = with_default.sub(lambda m: _value(m.group(1), m.group(2)), template)

    getenv = re.compile(rf'{{{{\s*getenv\s+"({ENV_NAME})"\s+"([^"]*)"\s*}}}}')
    template = getenv.sub(lambda m: _value(m.group(1), m.group(2)), template)

    env = re.compile(rf"{{{{\s*\.Env\.({ENV_NAME})\s*}}}}")
    template = env.sub(lambda m: _value(m.group(1)), template)

    if "{{" in template or "}}" in template:
        raise ValueError("unsupported template expression")
    return template


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--file")
    parser.add_argument("-o", "--out")
    args = parser.parse_args()

    source = Path(args.file).read_text(encoding="utf-8") if args.file else sys.stdin.read()
    result = render(source)
    if args.out:
        Path(args.out).write_text(result, encoding="utf-8")
    else:
        sys.stdout.write(result)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"gomplate: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc
