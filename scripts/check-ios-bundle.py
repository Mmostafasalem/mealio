"""Check the real build output, not just Xcode resource configuration."""
import argparse
import plistlib
from pathlib import Path
from xml.parsers.expat import ExpatError

parser = argparse.ArgumentParser()
parser.add_argument("bundle", type=Path)
args = parser.parse_args()
if not (args.bundle / "Info.plist").is_file():
    parser.error("Expected a built iOS .app bundle")

backend = Path(__file__).resolve().parent.parent / "smartmarket/smartmarket-backend"
forbidden = {p.name for p in backend.rglob("*") if p.is_file()}
forbidden.update({"CACHEDIR.TAG", "nodeids", "lastfailed", "stepwise"})
forbidden.update({"Secrets.xcconfig", "Secrets.xcconfig.example", "Build.xcconfig", ".env"})
leaks = sorted(str(p.relative_to(args.bundle)) for p in args.bundle.rglob("*")
               if p.is_file() and (p.name in forbidden or p.name.startswith(".env.")
                                   or p.suffix in {".py", ".pyc", ".xcconfig"}))
missing = [name for name in ("Privacy.md", "Support.md") if not (args.bundle / name).is_file()]
try:
    reviewed = backend.parent / "PrivacyInfo.xcprivacy"
    privacy_matches = (plistlib.loads((args.bundle / "PrivacyInfo.xcprivacy").read_bytes())
                       == plistlib.loads(reviewed.read_bytes()))
except (OSError, ValueError, plistlib.InvalidFileException, ExpatError):
    privacy_matches = False
if leaks or missing or not privacy_matches:
    if leaks: print("Unexpected backend/build files in app:", ", ".join(leaks))
    if missing: print("Missing offline legal documents:", ", ".join(missing))
    if not privacy_matches: print("Privacy manifest missing, invalid or different from the reviewed source.")
    raise SystemExit(1)
print("Bundle check passed: reviewed privacy manifest and offline legal documents present; backend and build-secret files absent.")
