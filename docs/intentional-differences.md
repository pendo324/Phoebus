# Intentional differences from Apollo and Apollo Reborn

Phoebus aims to match Apollo for Reddit's design and Apollo Reborn's
features closely. This page lists the places where it deliberately does
not, and why.

## Accounts, notifications and extensions

- **Push notifications go through Bark or a self-hosted notification
  backend.** Phoebus has no APNs push: a build signed without a paid
  developer account has no push entitlement, so the backend delivers
  through Bark.
