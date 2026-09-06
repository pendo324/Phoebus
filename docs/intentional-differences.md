# Intentional differences from Apollo and Apollo Reborn

Phoebus aims to match Apollo for Reddit's design and Apollo Reborn's
features closely. This page lists the places where it deliberately does
not, and why.

## Crash reports

- **Crash reports are reviewed and exported by you.** The review screen
  has no hand-off to a developer feedback form, so there is no "Include
  Debug Logs" switch and no developer-only testing section; share a
  report with "Export Sanitized Report". Reports belong to the person
  running the app, not to Reborn's developers.

## Accounts, notifications and extensions

- **Push notifications go through Bark or a self-hosted notification
  backend.** Phoebus has no APNs push: a build signed without a paid
  developer account has no push entitlement, so the backend delivers
  through Bark.
