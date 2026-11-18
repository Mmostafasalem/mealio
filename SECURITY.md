# Mealio security notes

## Personal AI accounts (pending activation)
See [activation and verification](docs/AI_ACCOUNTS_SETUP.md). Apple identity is
signature/audience/issuer/expiry/nonce verified; authorization codes are exchanged
server-side. Session hashes, encrypted Apple grants and transactional daily quotas
require durable storage. No health data, chat text or AI answer is written to the
account DB: for each AI request it keeps only a hashed request key and a keyed
input fingerprint for 24 hours, so a repeated key is refused (409, "already
processed") and never rerun or replayed. The only AI output held anywhere is the
in-memory recipe cache (per account, at most 500 entries, cleared on account
deletion and restart). Details: smartmarket/smartmarket-backend/SECURITY.md.
Apple capability, persistent hosting, live provider checks and web authentication
remain release gates. Personal credits do not add free provider capacity.
