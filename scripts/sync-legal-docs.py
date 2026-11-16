"""Bundle canonical legal documents for iOS and the standalone web upload.

Run again after editing PRIVACY.md or SUPPORT.md, before building either app.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
destination = root / "smartmarket/Resources"
destination.mkdir(parents=True, exist_ok=True)
documents = {}
for source, name in [("PRIVACY.md", "Privacy.md"), ("SUPPORT.md", "Support.md")]:
    content = (root / source).read_text(encoding="utf-8")
    (destination / name).write_text(content, encoding="utf-8")
    documents[Path(source).stem.lower()] = content

web_destination = root / "web/content/legal.json"
web_destination.parent.mkdir(parents=True, exist_ok=True)
web_destination.write_text(
    json.dumps(documents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print("Updated bundled iOS and web privacy and support documents.")
