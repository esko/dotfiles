# Encrypted host secrets

Files in this directory are SOPS-encrypted, one file per deployment. They follow
the schema documented in [`../README.md`](../README.md).

Create or update deployment secrets with:

```sh
nix run .#bootstrap-secrets -- ssh <deployment>
nix run .#bootstrap-secrets -- env <deployment> <key>
```
