# Contributing

Thank you for helping improve the labs. Issues and pull requests are welcome.

## Ground rules

* **No secrets.** Never commit `.env`, connection strings, NROD/RDM passwords or keys. CI and reviewers reject them.
* **No invented APIs.** If you add automation, link the official documentation for every endpoint, payload or CLI
  command in the PR description. Anything you can't verify must be marked `TODO(verify)`.
* **UK English** in documentation.
* Keep every lab runnable in two ways: **Option A** (script) and **Option B** (manual steps). If you change one,
  update the other.
* Respect data licences: attribute sources, don't call anything "official", and don't use Network Rail or National Rail logos.

## Development

```bash
cd src/bridge
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
ruff check . && python -m pytest -q
```

Unit tests must not need network access. Add sample messages under `src/bridge/tests/fixtures/`.

Infrastructure: `az bicep build --file infra/main.bicep` and `az bicep lint --file infra/main.bicep`.

Scripts: keep the `.sh` and `.ps1` versions in step. CI runs ShellCheck and the PowerShell parser.

## Pull requests

1. Fork the repo and create a feature branch.
2. Make small, focused changes. Update the relevant `docs/labs/*.md`.
3. Make sure CI is green (`bridge-ci`, `infra-validate`).
4. Describe how you tested, including which Fabric and Azure regions you used.
