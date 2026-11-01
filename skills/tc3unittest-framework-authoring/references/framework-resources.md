# Framework resources and compatibility

The skill has its own version, independent of the PLC library. The entry's metadata identifies the framework version used for its integration guidance. Initially this is Tc3_UnitTest 1.0.0.0, namespace Tc3UnitTest. A matching version is necessary; package provenance and input hashes identify the exact saved sources. Consumer library parameters can differ from documented defaults.

## Installed package

The standalone package includes a generated framework/ directory beside SKILL.md:

- docs/authoring/: the maintained user-facing Authoring Guide and AI-assisted authoring chapter.
- contracts/: the PLC-owned framework contracts.
- api/index.md and api/types/: generated consumer declarations, protected extension points, parameter descriptions/defaults and inheritance references. Locate the type in the index, then read its JSON entry and necessary base/interface entries. These are documentation snapshots, not a stable interchange format or executable implementation. Private implementation storage is excluded; required internal declaration dependencies retain their visibility.

Resolve paths such as docs/authoring/test-case.md from this framework/ root. Read the chapter relevant to the requested task rather than all resources. The package manifest records original input hashes and generated file hashes. It does not certify a consuming project's binary or parameter configuration.

## Install and invoke with Codex

For project-local use, extract the complete tc3unittest-framework-authoring/
package directory so its entry in the consuming repository is
.agents/skills/tc3unittest-framework-authoring/SKILL.md, with references/, assets/
and the bundled framework/ alongside it. Do not add another archive-name level
or copy only SKILL.md. Inspect an existing installation before replacing it;
avoid simultaneously loading duplicate copies with the same skill name.

Start Codex in that repository. Select the skill through /skills or explicitly
mention $tc3unittest-framework-authoring in the request, for example:

> Use $tc3unittest-framework-authoring to analyze the supplied block and
> requirements and propose a proportionate test plan. Do not implement it yet.

For implementation, supply the agreed scenarios and request their implementation
directly; the skill must not force a second round of test-intent discovery.
Codex can also select a matching skill implicitly. If a new or updated skill
does not appear, restart Codex. See the
[official local-skill guidance](https://learn.chatgpt.com/docs/build-skills#where-to-save-skills)
for host discovery details.

Installing this instruction package does not install the PLC library, change
Codex permissions or configure engineering tools. Framework library setup is
described in docs/authoring/framework-model.md under the framework resource root.

## Source development or another framework version

The canonical skill source deliberately does not store generated snapshots. When framework/ is absent, use the matching framework checkout's docs/authoring/ and contracts/ plus its saved public declarations or matching API help. Optional SelfTests mentioned in integration guidance are development examples, not required package resources. Do not require internal skill projects, evaluation answers or repository workflow instructions.

For another framework version, obtain its matching guidance/declarations and review relevant signature and behavior differences before implementation. Do not assume compatibility with an unverified future version. Report missing framework information specifically; do not invent an API or substitute a stale bundled snapshot. Block analysis and test selection remain possible without engineering tooling.

## Host and execution boundary

Codex is the primary verification target. Behavioral guidance uses ordinary Markdown and relative resources; agents/openai.yaml is optional host metadata. Another agent may consume the core, but equivalent output or verified execution support is not claimed. Read-only source inspection can use available files or authorized engineering access; builds, deployment and PLC control are separate operations outside this skill. The package grants no tool, installation, engineering or runtime permissions and requires no particular MCP server.

Codex CLI 0.166.0 was used for bounded packaged block-analysis/test-planning and supplied-intent implementation exercises. Such evidence covers the recorded tasks and environment, not a minimum supported CLI version, every model or every future output. Host access/output capability can differ from requested flags. Source/template checks, native compilation of a selected generated candidate and actual PLC runtime verification establish different claims; successful packaging alone establishes none of the latter two. Fixture assumptions and generated code still require review. No general skill/no-skill benefit or arbitrary-project success rate is established.
