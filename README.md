# TC3 UnitTest

PLC-side unit test framework for Beckhoff TwinCAT 3 projects.

TC3 UnitTest is developed as an independent PLC library with TwinCAT-specific runtime integration, contracts, coding conventions, and development tooling.

## Purpose

TC3 UnitTest provides reusable PLC-side building blocks for testing TwinCAT PLC logic in a TwinCAT runtime.

The intended scope includes:

- PLC-side execution of UnitTest runs, Test Suites, and Test Cases,
- reusable preparation and assertion concepts,
- structured lifecycle, result, aggregation, and diagnostic information,
- a PLC-owned interface contract consumed by an external PC-side runner,
- automated execution and evaluation in CI-oriented workflows.

## Scope

This repository owns the TwinCAT PLC library and its PLC-facing and PLC/PC contracts. The separate PC runner and its TwinCAT runtime access profile are not part of this repository.

## Build and library use

The development project contains the framework, its selftests and the selftest runtime composition. Native `.compiled-library` and `.library` packages contain the Framework area only; a consuming PLC project supplies its own tests and cyclic composition.

Use TwinCAT 3.1 Build 4026. The verified local consumer configuration is `Release|TwinCAT OS (x64)` on a Windows Usermode Runtime; this does not establish support for other targets or build lines.

For installation, dependencies and library parameters, start with [Using the packaged library](docs/authoring/framework-model.md#using-the-packaged-library). Open the matching standalone HTML help by extracting its ZIP and opening `index.html`; no documentation server or TE1030 license is required.

To rebuild and check the saved development project offline:

```powershell
.\tools\build\build.ps1
```

Open the authoritative solution at `projects/Tc3UnitTest.4026/Tc3UnitTest.4026.sln`. Interactive engineering and the repository build use this same versioned solution. Build evidence remains ignored below `artifacts/`.

## Documentation

- [Framework architecture](docs/framework-architecture.md)
- [Authoring manual: framework model](docs/authoring/framework-model.md)
- [TwinCAT project layout](docs/project-layout.md)
- [Build and validation workflow](docs/build-workflow.md)
- [Offline HTML help generation and delivery](tools/documentation/README.md)
- [Framework selftest strategy](docs/selftest-strategy.md)
- [Contracts](contracts/README.md)

The authoring manual starts with the framework model and separates practical guidance for Test Cases, Preparations, Assertions, Test Suites and Run Control.

## Author

[Lorenz Software](https://www.lorenz-software.solutions/)

Contact: [mail@lorenz-software.net](mailto:mail@lorenz-software.net)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
