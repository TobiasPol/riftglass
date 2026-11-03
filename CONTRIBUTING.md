# Contributing

1. `scripts/bootstrap.sh` (installs nothing without asking), then `scripts/test.sh`.
2. Keep files under 300 lines and functions under 50 (SwiftLint enforces this). Run `scripts/lint.sh --fix`.
3. Logic belongs in the packages (`LeagueKit`, `DataKit`, `StatsKit`, `OverlayKit`) with Swift Testing tests;
   the app target only wires things together.
4. Fixtures recorded from a real client must be anonymized (`scripts/spike/lib.sh: anonymize`). The
   pre-commit hook runs gitleaks; never commit tokens, `.env` files or raw spike output.
5. Features must respect [docs/COMPLIANCE.md](docs/COMPLIANCE.md). PRs adding enemy timers, memory
   reading, injection or input automation will be closed.
6. Before changing LCU behaviour, check [docs/SPIKE.md](docs/SPIKE.md): several community-documented
   behaviours differ on macOS.
