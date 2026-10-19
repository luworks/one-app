# Today

Today (formerly "one.") is the native iPhone planner for calendar, reminders and alarms. Data stays local; AI proposes changes with Add/Apply and Undo. The HTML prototype in `src/` is an older design reference.

Start with [product principles](CLAUDE.md), [iOS development and troubleshooting](ios/README.md), and the [linked-module architecture](docs/engineering/architecture.md). [AGENTS.md](AGENTS.md) defines contribution and verification rules.

Run all local/CI engineering commands through `./dev` from this repository root:

```sh
./dev help
./dev doctor
./dev bootstrap
./dev generate
./dev resolve
./dev build Debug
./dev test unit
```

`doctor` is read-only; bootstrap installs pinned worktree-local tools and runtimes. Builds, simulator journeys, unsigned archives, signed releases and physical-device acceptance are separate evidence. See the iOS guide before using shared host resources or release commands.

## License

MIT — see [LICENSE](LICENSE).
