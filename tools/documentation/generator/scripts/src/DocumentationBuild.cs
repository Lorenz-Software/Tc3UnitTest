using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

static class DocumentationBuild
{
    public static void Run(string repo, string output, string configurationPath, string templatePath)
    {
        var evidence = new BuildEvidence();
        evidence.Add("configuration/project.json", configurationPath);
        var config = ProjectConfiguration.Load(configurationPath);
        string framework = ProjectConfiguration.ConfinedPath(repo, config.SourceRoot);
        var selected = config.IncludeTypes;
        var candidates = Directory.EnumerateFiles(framework, "*", SearchOption.AllDirectories)
            .Where(p => new[] { ".TcPOU", ".TcIO", ".TcDUT", ".TcGVL" }.Contains(Path.GetExtension(p), StringComparer.OrdinalIgnoreCase)).ToList();
        var sourceFiles = (config.Selection == null ? selected.Select(name => {
            var matches = candidates.Where(p => Path.GetFileNameWithoutExtension(p) == name).ToList();
            if (matches.Count != 1) throw new FormatException($"Selected type '{name}' must resolve exactly once; found {matches.Count}.");
            return matches[0];
        }) : candidates).Order().ToList();
        var repositoryInputs = sourceFiles.Concat(config.Selection == null ? [] : new[] { ProjectConfiguration.ConfinedPath(repo, config.Selection.ProjectFile) }).Concat(LibraryMetadata.Inputs(config.Library).Select(p => ProjectConfiguration.ConfinedPath(repo, p)))
            .Concat(config.Guide == null ? [] : config.Guide.Chapters.Select(c => ProjectConfiguration.ConfinedPath(
                ProjectConfiguration.ConfinedPath(repo, config.Guide.SourceRoot), c.File)))
            .Append(ProjectConfiguration.ConfinedPath(repo, config.Attribution.LicenseFile)).Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var input in repositoryInputs) evidence.Add("repository/" + Path.GetRelativePath(repo, input), input);
        foreach (var relative in new[] { config.Stylesheet, config.Attribution.LogoFile, config.Attribution.HeaderLogoFile }.OfType<string>().Distinct())
            evidence.Add("configuration/" + relative, ProjectConfiguration.ConfinedPath(Path.GetDirectoryName(configurationPath)!, relative));
        foreach (var input in Directory.EnumerateFiles(templatePath, "*", SearchOption.AllDirectories))
            evidence.Add("template/" + Path.GetRelativePath(templatePath, input), input);
        evidence.Add("generator/assembly", typeof(DocumentationBuild).Assembly.Location);
        var identity = BuildEvidence.Git(repo);
        var metadata = LibraryMetadata.Read(repo, config);
        if (metadata != null) config = config with { LibraryNamespace = metadata.Namespace, Publisher = metadata.Company };
        var before = sourceFiles.ToDictionary(p => p, BuildEvidence.Hash);
        List<Api> apis;
        object[] coverage = [];
        if (config.Selection != null) {
            var resolved = ApiSelection.Resolve(repo, config, sourceFiles);
            config = resolved.Config; apis = resolved.Apis; coverage = resolved.Coverage; selected = config.IncludeTypes;
        } else apis = sourceFiles.SelectMany(p => Parser.Read(p, repo, config.LibraryNamespace!)).ToList();
        Directory.CreateDirectory(output);
        HelpRenderer.Save(Path.Combine(output, "export-coverage.json"), coverage);
        if (apis.Select(a => a.Uid).Distinct().Count() != apis.Count) throw new FormatException("Duplicate API identifier.");
        Directory.CreateDirectory(output);
        var guide = GuidePresentation.Read(repo, config.Guide, apis);
        HelpRenderer.Render(apis, config, output, templatePath,
            ProjectConfiguration.ConfinedPath(Path.GetDirectoryName(configurationPath)!, config.Stylesheet),
            ProjectConfiguration.ConfinedPath(repo, config.Attribution.LicenseFile),
            config.Attribution.LogoFile == null ? null : ProjectConfiguration.ConfinedPath(Path.GetDirectoryName(configurationPath)!, config.Attribution.LogoFile),
            config.Attribution.HeaderLogoFile == null ? null : ProjectConfiguration.ConfinedPath(Path.GetDirectoryName(configurationPath)!, config.Attribution.HeaderLogoFile), guide, metadata, identity);
        evidence.Verify();
        var finalIdentity = BuildEvidence.Git(repo);
        if (finalIdentity != identity) throw new IOException("Git source identity changed during documentation generation.");
        HelpRenderer.Save(Path.Combine(output, "help-build.json"), new {
            library = metadata, source = identity, inputHashes = evidence.Hashes,
            note = "Saved-source documentation. Parameter values are consumer-overridable defaults. Per-object semantic versions are not inferred from XML format versions."
        });
        string[] primitive = ["BOOL", "INT", "UINT", "DINT", "UDINT", "LINT", "LREAL", "REAL", "STRING"];
        var externalTypes = apis.SelectMany(a => a.Fields.Select(f => f.Type).Concat(a.ReturnType == null ? [] : new[] { a.ReturnType }))
            .Where(t => !primitive.Contains(t) && !t.StartsWith("STRING(") && !apis.Any(a => a.Owner == null && a.Name == t)).Distinct().Order().ToArray();
        HelpRenderer.Save(Path.Combine(output, "probe-report.json"), new {
            status = "generated; DocFX rendering verification is a separate step", types = selected.Count, pages = apis.Count, selection = config.Selection == null ? "Explicit object names" : "Public Compile sources plus required declaration dependencies",
            preservedSources = before.All(p => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p.Key))) == p.Value),
            sourceHashes = before.ToDictionary(p => Path.GetRelativePath(repo, p.Key).Replace('\\', '/'), p => p.Value),
            guideChapters = guide.Count,
            preservedGuideSources = guide.All(d => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(d.Source))) == d.Hash),
            guideSourceHashes = guide.ToDictionary(d => Path.GetRelativePath(repo, d.Source).Replace('\\', '/'), d => d.Hash),
            parametersAndFields = apis.Sum(a => a.Fields.Count), inheritedMembers = apis.Where(a => a.Owner == null).ToDictionary(a => a.Uid, a => HelpRenderer.Effective(a, apis).Where(m => m.Owner != a.Name).Select(m => m.Uid)),
            externalTypes, limitations = new[] { "Configured source boundary; Runtime and SelfTests are not implicitly included. Only the reviewed declaration subset is supported.", "STRUCT, UNION, enum and alias DUTs; one global-variable or constant block per GVL; unsupported forms fail.", "No constant evaluation or external library resolution.", "Reviewed documentation markup only; unsupported markup and conflicting descriptions fail explicitly.", "Generated YAML uses the JSON subset of YAML with the DocFX ApiPage MIME header.", "Plain-text ST code display; no ST syntax highlighting claimed.", "No MCP server, normative schema, PLC modification or runtime access." }
        });
        Console.WriteLine($"Generated {apis.Count} API pages from {selected.Count} saved TwinCAT XML files.");
    }

}
