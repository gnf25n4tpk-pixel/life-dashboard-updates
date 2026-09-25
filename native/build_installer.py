#!/usr/bin/env python3
"""Package the verified dashboard, native Swift bridge and icon for macOS."""
import base64
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT / "update.json").read_text())
dashboard = b"".join((ROOT / name).read_bytes() for name in manifest["dashboardParts"])
assert hashlib.sha256(dashboard).hexdigest() == manifest["sha256"]
assert manifest["dashboardVersion"] == "0.19.2"
assert manifest["minimumNativeVersion"] == "0.13.0"

icon_b64 = (ROOT / "AppIcon.png.b64").read_text().strip()
icon = base64.b64decode(icon_b64)
assert hashlib.sha256(icon).hexdigest() == manifest["resources"][0]["sha256"]

template = (ROOT / "native/installer.template.command").read_text()
content = template
for name, data in (
    ("DASHBOARD", dashboard),
    ("SWIFT", (ROOT / "native/LifeDashboard.swift").read_bytes()),
    ("ICON", icon),
):
    content = content.replace("{{" + name + "_B64}}", base64.b64encode(data).decode())
assert "{{" not in content

command_name = "Install-Life-Dashboard-Desktop-v13.command"
command_path = ROOT / command_name
command_path.write_text(content)
command_path.chmod(0o755)

zip_path = ROOT / "Install-Life-Dashboard-Desktop-v13.zip"
info = ZipInfo(command_name, date_time=(2026, 9, 25, 0, 0, 0))
info.compress_type = ZIP_DEFLATED
info.external_attr = 0o100755 << 16
with ZipFile(zip_path, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
    archive.writestr(info, content)
print(zip_path.name, zip_path.stat().st_size, "bytes")
