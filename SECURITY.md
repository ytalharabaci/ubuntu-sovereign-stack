# Security Policy

## Supported versions

**None.** The repository was archived on 2026-10-17 and is no longer
maintained. No security fixes will be made, and pinned component versions will
not be updated. Treat everything here as reference material: review and update
all versions and configurations before reusing any part of it.

## Reporting a vulnerability

The repository is archived, so no fixes will be published. If you find an issue
that also affects an upstream component (RKE2, Authentik, Longhorn, Velero,
etc.), report it to that project directly.

## Secret handling

- No credentials are stored in this repository. Kubernetes Secrets are generated
  in-cluster by `scripts/bootstrap-secrets.sh`; the Compose variant reads them
  from a git-ignored `small-scale/.env` (template: `.env.example`).
- **Historical note:** commits before the 2026-10 hardening change contained
  hardcoded demo credentials (Authentik, Grafana, Rancher bootstrap, MinIO/Velero,
  Samba, `small-scale/.env`). They were placeholder values that were never used in
  a real environment, and they are **invalid**. Never reuse them. If you deployed
  from an older commit, rotate every credential (see `docs/OPERATIONAL_RUNBOOK.md`).

## Automated security checks

Every push and pull request to `main` runs `.github/workflows/ci.yml`:

| Check | Tool | Fails on |
| --- | --- | --- |
| Secret scanning (working tree) | gitleaks | any detected secret |
| IaC misconfiguration | Trivy (`config`) | HIGH / CRITICAL findings not justified in `.trivyignore.yaml` |
| Kubernetes schema | kubeconform (strict, incl. CRDs) | invalid manifests |
| Ansible | ansible-lint (production profile) + syntax check | lint errors |
| Shell | ShellCheck | warnings |
| YAML | yamllint (strict) | errors/warnings |
| Compose | `docker compose config` | invalid compose files |

Third-party GitHub Actions are pinned by commit SHA.

**Recommended repository settings** (configure in GitHub, not in code):
enable branch protection on `main`, require the CI jobs above to pass and at
least one review before merging, and enable GitHub secret scanning with push
protection and Dependabot alerts.

## Scope and limitations

The checks above are static. They do not replace a live penetration test,
runtime policy enforcement or a verified restore drill. See
[docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) for what has actually been verified.
