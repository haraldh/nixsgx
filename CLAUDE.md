# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

nixsgx is a Nix flake providing reproducible packages for Intel SGX SDK, DCAP attestation, and Gramine runtime. All builds target reproducibility for enclave image construction. Maintained by Harald Hoyer; goal is eventual nixpkgs upstreaming.

## Build Commands

```bash
# Format check (CI runs this)
nix fmt . -- --check

# Type-check all packages
nix flake check -L --show-trace --keep-going

# Build all outputs
nix run github:nixos/nixpkgs/nixos-25.05#nixci -- build

# Build a specific package
nix build .#packages.x86_64-linux.sgx-sdk
nix build .#nixsgx-test-sgx-dcap

# Integration test (what CI does)
nix build --accept-flake-config -L .#nixsgx-test-sgx-azure
docker load -i result
docker run -i --env GRAMINE_DIRECT=1 --privileged --init --rm nixsgx-test-sgx-azure:latest
```

Formatter is `nixpkgs-fmt` (configured in `flake.nix` outputs-builder).

## Architecture

**Flake structure** uses [snowfall-lib](https://github.com/snowfallorg/lib) with namespace `nixsgx`. Packages are auto-discovered from `packages/*/default.nix`. Overlays live in `overlays/`.

**Package dependency chain:**
- `sgx-sdk` (2.25) → `sgx-ssl` (OpenSSL 3.0 for enclaves)
- `sgx-psw` → `sgx-sdk` + prebuilt Architectural Enclaves
- `sgx-dcap` (1.22) → `sgx-sdk`, `sgx-ssl` + prebuilt DCAP enclaves (splits into 14+ outputs)
- `gramine` (1.8) → Python-based LibOS runtime, meson build system
- `azure-dcap-client` → alternative attestation for Azure environments
- Test packages (`nixsgx-test-sgx-{dcap,azure}`) → built via `sgxGramineContainer`

**`overlays/libTee/sgxGramineContainer.nix`** is the key abstraction: a function that takes packages + an entrypoint and produces a Docker container image with a Gramine-wrapped SGX enclave. It generates manifests, handles signing, configures trusted files, and supports both DCAP and Azure attestation modes.

## Nix Conventions in This Repo

- Packages disable hardening (`fortify`, `pie`, `stackprotector`) — required for enclave code
- Prebuilt Intel-signed enclaves are fetched via `fetchurl` and injected in `postUnpack`
- All packages `patchShebangs` in `postPatch`
- Patches are minimal and kept in each package directory
- `sgx-dcap` uses multiple outputs for granular dependency control

## Binary Cache

Attic cache at `https://attic.teepot.org/cache` is configured in `nixConfig` — speeds up builds significantly. CI uses `ATTIC_TOKEN` secret for cache writes.

## CI

GitHub Actions (`.github/workflows/nix.yml`) runs three jobs: `fmt`, `check`, `build`. The build job also runs an integration test loading the Azure test container and verifying `Hello, world!` output.
