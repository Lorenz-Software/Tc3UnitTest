using System.Globalization;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

sealed record ContractMetadata(string Title, string Version, string Source, string Constant);
sealed record LibraryMetadata(string Company, string Title, string Version, string Namespace, string FrameworkVersion, List<ContractMetadata> Contracts)
{
    internal static int[] VersionParts(string text, int count)
    {
        var parts = text.Split('.');
        if (parts.Length != count || parts.Any(p => !Regex.IsMatch(p, @"^(0|[1-9][0-9]*)$") || !ushort.TryParse(p, out _)))
            throw new FormatException("Invalid " + count + "-component version: " + text);
        return parts.Select(p => int.Parse(p, CultureInfo.InvariantCulture)).ToArray();
    }

    public static LibraryMetadata? Read(string repo, ProjectConfiguration config)
    {
        if (config.Library is not { } source) return null;
        string PathOf(string relative) => ProjectConfiguration.ConfinedPath(repo, relative);
        var project = XDocument.Load(PathOf(source.ProjectFile));
        string[] identityProperties = ["Company", "Title", "ProjectVersion", "DefaultNamespace"];
        if (project.Descendants().Any(e => identityProperties.Contains(e.Name.LocalName)
            && (e.Attribute("Condition") != null || e.Parent?.Attribute("Condition") != null)))
            throw new FormatException("Conditional library identity requires MSBuild evaluation and is not supported.");
        var groups = project.Root?.Elements().Where(e => e.Name.LocalName == "PropertyGroup" && e.Attribute("Condition") == null)
            ?? throw new FormatException("Missing project metadata.");
        string Property(string name)
        {
            var values = groups.SelectMany(g => g.Elements()).Where(e => e.Name.LocalName == name).ToList();
            if (values.Count != 1 || values[0].Attribute("Condition") != null || string.IsNullOrWhiteSpace(values[0].Value)
                || values[0].Value.Contains("$(")) throw new FormatException("Expected one unconditional literal project property: " + name);
            return values[0].Value.Trim();
        }
        string company = Property("Company"), title = Property("Title"), version = Property("ProjectVersion"), ns = Property("DefaultNamespace");
        var parts = VersionParts(version, 4);
        if (!Regex.IsMatch(ns, @"^[A-Za-z_][A-Za-z0-9_.]*$")) throw new FormatException("Invalid project namespace.");
        if (config.LibraryNamespace != null && config.LibraryNamespace != ns) throw new FormatException("Configured namespace differs from PLC project metadata.");
        if (config.Publisher != null && config.Publisher != company) throw new FormatException("Configured publisher differs from PLC project company.");
        var generated = Parser.Read(PathOf(source.GeneratedVersionFile), repo, ns).Single();
        var field = generated.Fields.SingleOrDefault(f => f.Name == source.GeneratedVersionSymbol && f.Type == "ST_LibVersion")
            ?? throw new FormatException("Missing generated ST_LibVersion: " + source.GeneratedVersionSymbol);
        var structure = Regex.Match(field.Default ?? "", @"^\(\s*iMajor\s*:=\s*(\d+)\s*,\s*iMinor\s*:=\s*(\d+)\s*,\s*iBuild\s*:=\s*(\d+)\s*,\s*iRevision\s*:=\s*(\d+)\s*,\s*nFlags\s*:=\s*\d+\s*,\s*sVersion\s*:=\s*'([^']+)'\s*\)$", RegexOptions.IgnoreCase);
        if (!structure.Success || !parts.SequenceEqual(Enumerable.Range(1, 4).Select(i => int.Parse(structure.Groups[i].Value, CultureInfo.InvariantCulture)))
            || structure.Groups[5].Value != version)
            throw new FormatException("Generated library version differs from ProjectVersion; save/regenerate the PLC metadata first.");
        string frameworkVersion = string.Join('.', parts.Take(3));
        var contracts = new List<ContractMetadata>();
        foreach (var contract in source.Contracts)
        {
            var matches = Regex.Matches(File.ReadAllText(PathOf(contract.File)), @"^\s*- Contract version: `([^`]+)`\s*$", RegexOptions.Multiline);
            if (matches.Count != 1) throw new FormatException("Expected one contract version: " + contract.File);
            string contractVersion = matches[0].Groups[1].Value;
            _ = VersionParts(contractVersion, 3);
            var constants = Parser.Read(PathOf(contract.ConstantsFile), repo, ns).Single();
            var constant = constants.Fields.SingleOrDefault(f => f.Name == contract.Constant)
                ?? throw new FormatException("Missing contract version constant: " + contract.Constant);
            if (constant.Default != "'" + contractVersion + "'")
                throw new FormatException("Contract version differs from PLC constant: " + contract.File + " / " + contract.Constant);
            var capacity = Regex.Match(constant.Type, @"^STRING\(([A-Za-z_][A-Za-z0-9_]*)\)$", RegexOptions.IgnoreCase);
            if (capacity.Success)
            {
                var length = constants.Fields.SingleOrDefault(f => f.Name == capacity.Groups[1].Value);
                if (length == null || !int.TryParse(length.Default, out int maximum) || contractVersion.Length > maximum || frameworkVersion.Length > maximum)
                    throw new FormatException("Version text exceeds its declared PLC capacity: " + contract.Constant);
            }
            else throw new FormatException("Unsupported contract version STRING capacity: " + constant.Type);
            contracts.Add(new(contract.Title, contractVersion, contract.File, constants.Name + "." + contract.Constant));
        }
        return new(company, title, version, ns, frameworkVersion, contracts);
    }

    public static IEnumerable<string> Inputs(LibraryMetadataSource? source) => source == null ? [] :
        new[] { source.ProjectFile, source.GeneratedVersionFile }.Concat(source.Contracts.SelectMany(c => new[] { c.File, c.ConstantsFile }));
}
