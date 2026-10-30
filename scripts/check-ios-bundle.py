"""Check the real build output, not just Xcode resource configuration."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("bundle", type=Path)
args = parser.parse_args()
if not (args.bundle / "Info.plist").is_file():
    parser.error("Expected a built iOS .app bundle")

backend = Path(__file__).resolve().parent.parent / "smartmarket/smartmarket-backend"
forbidden = {p.name for p in backend.iterdir() if p.is_file()}
forbidden.update({"Secrets.xcconfig", "Secrets.xcconfig.example", "Build.xcconfig", ".env"})
leaks = sorted(str(p.relative_to(args.bundle)) for p in args.bundle.rglob("*")
               if p.is_file() and (p.name in forbidden or p.name.startswith(".env.")
                                   or p.suffix in {".py", ".pyc", ".xcconfig"}))
missing = [name for name in ("Privacy.md", "Support.md") if not (args.bundle / name).is_file()]
if leaks or missing:
    if leaks: print("Unexpected backend/build files in app:", ", ".join(leaks))
    if missing: print("Missing offline legal documents:", ", ".join(missing))
    raise SystemExit(1)
print("Bundle check passed: offline legal documents present; backend and build-secret files absent.")
