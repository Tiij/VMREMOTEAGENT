#!/usr/bin/env python3
"""Synchronise les templates de setup.sh avec les fichiers réellement testés."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
setup = root / "setup.sh"
text = setup.read_text(encoding="utf-8")
for name in (
    "docker-compose.yml", "Caddyfile", "dashboard/index.html",
    "cloudcli/Dockerfile", "cloudcli/entrypoint.sh", "cloudcli/supervisord.conf",
    "scripts/update.sh", "scripts/snapshot.sh", "scripts/restore.sh",
    "scripts/factory-reset.sh", "scripts/auto-snapshot.sh",
    "scripts/status.sh", "scripts/doctor.sh",
):
    pattern = re.compile(
        r'((?:cat >|write_script) "\$INSTALL_DIR/' + re.escape(name)
        + r'"(?: 755)? <<\x27([^\x27]+)\x27\n).*?\n\2(?=\n)', re.S
    )
    content = (root / name).read_text(encoding="utf-8").rstrip("\n")
    text, count = pattern.subn(lambda m: m[1] + content + "\n" + m[2], text)
    if count != 1:
        raise SystemExit(f"Template introuvable ou ambigu : {name}")
setup.write_text(text, encoding="utf-8", newline="\n")
print("Templates setup.sh synchronisés.")
