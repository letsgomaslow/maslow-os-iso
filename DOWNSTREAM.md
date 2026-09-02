# Maslow OS ISO downstream

This repository is the x86_64 installer downstream for Maslow OS, based on
`omacom/omarchy-iso`.

## Branch policy

- `quattro` is a fast-forward-only mirror of upstream `quattro`.
- `maslow` is the public product branch and is never rebased after publication.
- Upstream changes reach `maslow` through reviewed merge commits or pull requests.

## Compatibility boundary

Visible installer identity is Maslow OS. Internal command names, paths,
environment variables, package names, service identifiers, and technical error
references remain Omarchy-compatible. The first supported architecture is
x86_64; this repository does not claim Apple Silicon or general ARM64 support.

## Preview build policy

Preview ISOs must be built with `--local-source` against the `maslow` branches
of `letsgomaslow/maslow-os` and `letsgomaslow/maslow-os-pkgs`. There is no
Maslow production package mirror or public update channel yet.

Do not sign, upload, or distribute a public binary until provenance, license
and trademark review, Maslow-owned signing, checksums, clean encrypted and
unencrypted installs, update validation, and rollback validation all pass.

## Upstream sync

1. Fetch `upstream` and fast-forward `quattro` to `upstream/quattro`.
2. Push the mirrored `quattro` without force.
3. Merge `quattro` into a review branch based on `maslow`.
4. Run `./test/maslow-branding` and `./test/all` on Linux.
5. Build the x86_64 ISO from clean sibling checkouts and complete the release gates.
6. Merge without rewriting public history.
