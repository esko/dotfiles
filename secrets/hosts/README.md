# Encrypted host secrets

Files in this directory are SOPS-encrypted, one file per deployment. They may
contain host-specific private material such as `ssh/id_ed25519`; plaintext
private keys must never be committed.

Create a deployment file through:

```sh
nix run .#bootstrap-ssh -- <deployment>
```
