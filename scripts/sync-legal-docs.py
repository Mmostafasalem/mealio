"""Bundle the reviewed policy/support text for offline in-app access."""
from pathlib import Path

destination = Path("smartmarket/Resources")
destination.mkdir(parents=True, exist_ok=True)
for source, name in [("PRIVACY.md", "Privacy.md"), ("SUPPORT.md", "Support.md")]:
    (destination / name).write_text(Path(source).read_text())
print("Updated bundled privacy and support documents.")
