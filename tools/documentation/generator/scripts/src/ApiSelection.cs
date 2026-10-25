using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

// Selection operates on saved Compile items, separately from presentation and
// project area names. Explicit exceptions must continue to resolve.
static class ApiSelection
{
    public static (ProjectConfiguration Config, List<Api> Apis, object[] Coverage) Resolve(
        string repo, ProjectConfiguration config, List<string> candidates)
    {
        var selection = config.Selection!;
        string project = ProjectConfiguration.ConfinedPath(repo, selection.ProjectFile);
        var document = XDocument.Load(project);
        if (document.Descendants().Where(e => e.Name.LocalName == "Compile").Any(e =>
            e.Attribute("Condition") != null || e.Parent?.Attribute("Condition") != null ||
            ((string?)e.Attribute("Include") ?? "").IndexOfAny(['*', '?', '$', '%']) >= 0))
            throw new FormatException("Compile selection requires unconditional literal source paths; MSBuild evaluation is unsupported.");
        var compiled = document.Descendants().Where(e => e.Name.LocalName == "Compile")
            .Select(e => Path.GetFullPath(Path.Combine(Path.GetDirectoryName(project)!, (string?)e.Attribute("Include") ?? throw new FormatException("Compile item has no Include."))))
            .ToList();
        if (compiled.Distinct(StringComparer.OrdinalIgnoreCase).Count() != compiled.Count)
            throw new FormatException("Duplicate Compile references.");
        if (candidates.Any(p => !compiled.Contains(p, StringComparer.OrdinalIgnoreCase)))
            throw new FormatException("Source root contains an unreferenced PLC object.");
        string sourceRoot = ProjectConfiguration.ConfinedPath(repo, config.SourceRoot) + Path.DirectorySeparatorChar;
        if (compiled.Any(p => p.StartsWith(sourceRoot, StringComparison.OrdinalIgnoreCase) && !File.Exists(p)))
            throw new FormatException("Missing saved Compile source.");
        var all = candidates.SelectMany(p => Parser.Read(p, repo, config.LibraryNamespace!)).ToList();
        var roots = all.Where(a => a.Owner == null).ToList();
        if (roots.Select(a => a.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != roots.Count)
            throw new FormatException("Duplicate source object names.");
        foreach (var exception in selection.Exclusions)
            if (!roots.Any(a => a.Name == exception.Name)) throw new FormatException("Stale export exclusion: " + exception.Name);
        var excluded = selection.Exclusions.ToDictionary(e => e.Name, e => e.Reason);
        var selected = roots.Where(a => a.Access == "PUBLIC" && !excluded.ContainsKey(a.Name)).ToList();
        for (int index = 0; index < selected.Count; index++)
        {
            var root = selected[index];
            var exposed = all.Where(a => a == root || a.Owner == root.Name).ToList();
            var text = string.Join(" ", exposed.SelectMany(a => a.Fields.Select(f => f.Type + " " + f.Default)
                .Concat(new[] { a.Base, string.Join(" ", a.Interfaces), a.ReturnType, a.Kind == "DUT" ? a.Declaration : null })));
            var names = Regex.Matches(text, @"\b[A-Za-z_][A-Za-z0-9_]*\b").Select(m => m.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var dependency in roots.Where(a => names.Contains(a.Name) && !selected.Contains(a)))
            {
                if (excluded.ContainsKey(dependency.Name)) throw new FormatException("Excluded object is required by exported declaration: " + dependency.Name);
                dependency.RequiredDependency = true; selected.Add(dependency);
            }
        }
        var groups = config.Groups.Select(g => g with { Types = selected.Where(a =>
            a.Source.StartsWith(config.SourceRoot.TrimEnd('/') + "/" + g.SourcePrefix!.Trim('/') + "/", StringComparison.OrdinalIgnoreCase)).Select(a => a.Name).Order().ToList() }).ToList();
        if (groups.SelectMany(g => g.Types).Count() != selected.Count || selected.Any(a => groups.Count(g => g.Types.Contains(a.Name)) != 1))
            throw new FormatException("Each selected object must match exactly one area prefix.");
        var result = all.Where(a => selected.Any(r => r.Name == (a.Owner ?? a.Name))).ToList();
        var coverage = roots.Select(a => (object)new { name = a.Name, source = a.Source, access = a.Access,
            included = selected.Contains(a), requiredDependency = a.RequiredDependency,
            reason = selected.Contains(a) ? a.RequiredDependency ? "Required by a consumer-visible declaration; source visibility is retained." : "Public consumer API."
                : excluded.GetValueOrDefault(a.Name, "Private/internal implementation; not referenced by an exported declaration.") }).ToArray();
        return (config with { IncludeTypes = selected.Select(a => a.Name).Order().ToList(), Groups = groups }, result, coverage);
    }
}
