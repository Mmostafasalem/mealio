# Mealio security notes

## Personal AI accounts (pending activation)
See [activation and verification](docs/AI_ACCOUNTS_SETUP.md). Apple identity is
signature/audience/issuer/expiry/nonce verified; authorization codes are exchanged
server-side. Session hashes, encrypted Apple grants and transactional daily quotas
require durable storage. No health/chat bodies are persisted in this account DB.
Apple capability, persistent hosting, live provider checks and web authentication
remain release gates. Personal credits do not add free provider capacity.
