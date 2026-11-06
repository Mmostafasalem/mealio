# Mealio release completion plan

Goal: complete all locally and account-accessible release work, with evidence;
never label signed-device, account-side or live-service checks complete without proof.

- [x] Inspect signing identities, service access and current deployment state.
- [x] Replace obsolete provider default using official production-model documentation;
  add no-secret staging/live diagnostic with explicit online/fallback verification.
- [x] Correct App Store/review/support copy for Apple AI sign-in, quotas and deletion.
- [x] Prepare privacy/support page source for existing web hosting, synchronizing
  legal source rather than inventing a public support mailbox or processor promises.
- [x] Add release preflight checks for auth/storage/config/model/readiness and a
  release-safe deployment configuration, with meaningful regression coverage.
- [x] Verify catalog estimate honesty, local native/backend/web/sync/privacy tests and build; wire CI. Remote CI is a separate check.
- [x] Produce a fresh device archive and attempt signing only if credentials exist.
- [ ] Complete authorized accessible deployments only after compatibility checks;
  avoid breaking the existing web proxy with unintegrated personal authentication.
- [x] Record current release evidence and the exact external owner-only blockers.

Constraints: no secrets in chat; no fabricated retailer prices/promotions; no new
third-party iOS dependencies; preserve palette/interaction work. Do not accept
Apple legal agreements, buy hosting/membership, invent a support contact or claim
physical-device acceptance from simulator tests. No automatic branch merge.

Deployment remains blocked by unavailable hosting access; Apple membership and support contact are not yet set up. See docs/RELEASE_STATUS_2026-11-06.md for evidence and owner-only prerequisites.

Final outcome: candidate source committed locally; attempted separate release-check branch push was rejected by GitHub authentication. Remote CI did not run. All available local checks passed; external deployment/signing remains blocked.
