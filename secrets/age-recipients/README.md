# Public age recipients

Each file contains the public age recipient for one deployment. The matching
age private identity remains host-local at `~/.config/sops/age/keys.txt` and
must never be committed.

The bootstrap app regenerates `.sops.yaml` with one path-specific rule per
recipient, so deployments cannot decrypt one another's host secret files.
