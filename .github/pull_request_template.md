## What and why

<!-- What this changes, and the Apollo or Apollo Reborn behaviour it matches. Link any issue it fixes. For a Reborn port, name the feature and its PR as plain text, e.g. "Ported from Apollo Reborn `Apollo-Reborn#1305` by <author name>": no @mentions or links to Reborn PRs or issues, since those notify Reborn's contributors. -->

## Testing

- [ ] `scripts/smoke.sh` prints `SMOKE: ok (N passed)` and the iOS build succeeds
- [ ] Checked in the iOS Simulator
- [ ] Checked on a device <!-- say what could only be checked there -->

## Screenshots

<!-- For UI changes: Phoebus next to Apollo where you can. Delete this section otherwise. -->

## Checklist

- [ ] The title follows [Conventional Commits](https://www.conventionalcommits.org) (`feat: …`, `fix: …`), since it decides the next release version
- [ ] Deliberate differences from Apollo are listed in `docs/intentional-differences.md`
- [ ] No Apollo binaries, artwork or credentials, and no Apollo Reddit client ID
- [ ] Reborn credit uses plain names and backticked PR numbers (no @mentions, links or `Co-authored-by`)
