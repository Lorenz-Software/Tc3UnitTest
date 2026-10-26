# Contributing to TC3 UnitTest

Bug reports, documentation improvements, and focused pull requests are welcome.
The [Framework Model](docs/authoring/framework-model.md) introduces the components
and their responsibilities.

## Questions and Bug Reports

Use [Discussions](https://github.com/Lorenz-Software/Tc3UnitTest/discussions) for
questions and ideas, and [Issues](https://github.com/Lorenz-Software/Tc3UnitTest/issues)
for reproducible problems. Check existing reports before opening a new one.

Include the following where relevant:

- TC3 UnitTest library version or source commit.
- TwinCAT engineering and runtime builds, runtime type, and target architecture.
- A minimal Structured Text example or steps to reproduce, including the starting conditions.
- Expected behavior and actual behavior.
- Assertion names/results and relevant logs or event captures, if available.
- When using the PC application: PLCSIM.UnitTest version, access profile, and whether the run used WPF or CLI.

Report problems specific to the PC application in the
[PLCSIM.UnitTest repository](https://github.com/Lorenz-Software/PLCSIM.UnitTest).
For PLC/PC integration problems, include both sides' versions and observations.
Remove credentials and confidential project information from attachments.

## Pull Requests

- Keep each change focused on one problem or improvement.
- Explain the problem, resulting behavior, and checks performed. Link an existing report when available.
- Add or update relevant regression tests when framework or tooling behavior changes.
- Update affected documentation and examples alongside the implementation.

Discuss changes to public APIs, lifecycle semantics, result handling, or PLC/PC
contracts before implementation. Follow the
[architecture](docs/framework-architecture.md) and [public contracts](contracts/README.md).

Use English for code comments and documentation, and preserve the existing
formatting and CRLF line endings. Keep generated libraries, help archives,
build output, and local engineering state out of commits.

## Validation

Run checks appropriate to the change:

- **Documentation:** verify Markdown formatting and affected links.
- **PLC code:** follow the [build workflow](docs/build-workflow.md) and select relevant coverage using the [selftest strategy](docs/selftest-strategy.md).
- **Tooling:** run the affected tool's documented offline checks.

Native PLC validation requires the documented TwinCAT Build 4026 environment.
Report offline builds, consumer checks, and runtime tests separately, including
their environment and results. State which checks you could not perform.

## License

TC3 UnitTest is provided under the [MIT license](LICENSE).
