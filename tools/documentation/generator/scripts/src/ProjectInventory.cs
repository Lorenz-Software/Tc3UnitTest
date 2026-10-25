using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Xml.Linq;

namespace TwinCatDocumentation;

// Saved-source inventory only. Observations never certify documentation quality.
sealed record InventoryItem
{
    public required string Id { get; init; }
    public required string Path { get; init; }
    public required string Area { get; init; }
    public required string QualifiedName { get; init; }
    public required string Kind { get; init; }
    public required string SourceHash { get; init; }
    public string? Parent { get; init; }
    public int Line { get; init; }
    public string Visibility { get; init; } = "Unspecified";
    public string Role { get; init; } = "Requires classification";
    public string Signature { get; init; } = "";
    public string Direction { get; init; } = "";
    public string DeclaredType { get; init; } = "";
    public string? Initializer { get; init; }
    public string DocumentationForm { get; init; } = "Not observed";
    public string DeclarationForm { get; init; } = "";
    public string NativeCommentForm { get; init; } = "Not observed";
    public bool NamedParamMarkupObserved { get; init; }
    public string NativeComment { get; init; } = "";
    public List<string> CandidateFlags { get; init; } = [];
    public Dictionary<string, string> Review { get; init; } = new() {
        ["formatAndElements"] = "Open", ["meaning"] = "Open", ["savedSourcesAndOfflineChecks"] = "Open",
        ["nativeXae"] = "Open", ["html"] = "Open", ["classification"] = "Open"
    };
}

sealed record InventoryArea(string Prefix, string Name, string Role);
sealed record InventoryExclusion(string Path, string Reason);
sealed record InventoryScope(List<InventoryArea> Areas, List<InventoryExclusion> ExcludedDirectories);

static class ProjectInventory
{
    static readonly HashSet<string> SourceExtensions = new(StringComparer.OrdinalIgnoreCase) { ".TcPOU", ".TcDUT", ".TcIO", ".TcGVL" };
    static readonly HashSet<string> VariableBlocks = new(StringComparer.OrdinalIgnoreCase) {
        "VAR", "VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT", "VAR_GLOBAL", "VAR_TEMP", "VAR_INST", "VAR_STAT", "VAR_EXTERNAL", "VAR_CONFIG"
    };
    static readonly HashSet<string> Headers = new(StringComparer.OrdinalIgnoreCase) { "FUNCTION_BLOCK", "FUNCTION", "PROGRAM", "INTERFACE", "TYPE", "METHOD", "PROPERTY" };
    static string Plain(string text) => Regex.Replace(text, @"\s+", " ").Trim();
    static bool Is(Token token, string word) => token.Text.Equals(word, StringComparison.OrdinalIgnoreCase);
    static string Comment(Token token) => token.Text.StartsWith("//!") ? token.Text[3..].Trim()
        : token.Text.StartsWith("//") ? token.Text[2..].TrimStart('/').Trim() : token.Text.StartsWith("(*!") ? token.Text[3..^2].Trim() : token.Text[2..^2].Trim();
    static string Slice(string text, List<Token> tokens) => tokens.Count == 0 ? "" : Plain(text[tokens[0].Start..tokens[^1].End]);
    static int XmlLine(XElement node) => node is System.Xml.IXmlLineInfo line ? line.LineNumber : 1;

    public static void Run(string repo, string projectPath, string output, string? scopePath = null)
    {
        string projectRoot = Path.GetDirectoryName(projectPath)!;
        string Relative(string path) => Path.GetRelativePath(repo, path).Replace('\\', '/');
        var scope = scopePath == null ? new InventoryScope([], []) : JsonSerializer.Deserialize<InventoryScope>(File.ReadAllText(scopePath), new JsonSerializerOptions {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase, RespectRequiredConstructorParameters = true,
            UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
        }) ?? throw new FormatException("Missing inventory scope.");
        foreach (var area in scope.Areas) _ = ProjectConfiguration.ConfinedPath(projectRoot, area.Prefix);
        foreach (var excluded in scope.ExcludedDirectories)
        {
            _ = ProjectConfiguration.ConfinedPath(projectRoot, excluded.Path);
            if (string.IsNullOrWhiteSpace(excluded.Reason)) throw new FormatException("Inventory exclusion requires a reason.");
        }
        if (scope.Areas.Select(a => a.Prefix).Distinct(StringComparer.OrdinalIgnoreCase).Count() != scope.Areas.Count)
            throw new FormatException("Duplicate inventory area prefix.");
        bool Excluded(string path) => scope.ExcludedDirectories.Any(e => path.StartsWith(ProjectConfiguration.ConfinedPath(projectRoot, e.Path) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase));
        var project = XDocument.Load(projectPath, LoadOptions.SetLineInfo);
        var compile = project.Descendants().Where(n => n.Name.LocalName == "Compile" && n.Attribute("Include") != null).ToList();
        var paths = compile.Select(n => ProjectConfiguration.ConfinedPath(projectRoot, n.Attribute("Include")!.Value.Replace('\\', Path.DirectorySeparatorChar))).ToList();
        if (paths.Distinct(StringComparer.OrdinalIgnoreCase).Count() != paths.Count) throw new FormatException("Duplicate Compile references.");
        if (paths.Any(p => !File.Exists(p))) throw new FileNotFoundException("Missing Compile references: " + string.Join(", ", paths.Where(p => !File.Exists(p))));
        if (compile.Any(n => n.Attribute("Condition") != null || n.Parent?.Attribute("Condition") != null)) throw new FormatException("Conditional Compile references need explicit evaluation.");
        if (project.Descendants().Any(n => n.Name.LocalName == "Import" || n.Name.LocalName == "Compile" && (n.Attribute("Update") != null || n.Attribute("Remove") != null)))
            throw new FormatException("Imported/updated/removed Compile items need explicit evaluation before inventory acceptance.");
        if (paths.Any(Excluded)) throw new FormatException("Compiled source is inside an excluded directory; reconcile the scope.");
        var unreferenced = Directory.EnumerateFiles(projectRoot, "*", SearchOption.AllDirectories)
            .Where(p => SourceExtensions.Contains(Path.GetExtension(p)) && !Excluded(p) && !paths.Contains(p, StringComparer.OrdinalIgnoreCase)).ToList();
        if (unreferenced.Count != 0) throw new FormatException("Unreferenced PLC source files: " + string.Join(", ", unreferenced.Select(Relative)));
        var evidence = new BuildEvidence();
        evidence.Add(Relative(projectPath), projectPath);
        if (scopePath != null) evidence.Add("scope/" + Path.GetFileName(scopePath), scopePath);
        List<InventoryItem> items = [];
        var fileRows = new List<object>();
        foreach (string path in paths.Order(StringComparer.OrdinalIgnoreCase))
        {
            evidence.Add(Relative(path), path);
            string relative = Relative(path), local = Path.GetRelativePath(projectRoot, path).Replace('\\', '/');
            var selectedArea = scope.Areas.OrderByDescending(a => a.Prefix.Length).FirstOrDefault(a => local.StartsWith(a.Prefix.Replace('\\', '/').TrimEnd('/') + "/", StringComparison.OrdinalIgnoreCase));
            string area = selectedArea?.Name ?? (local.Contains('/') ? local.Split('/')[0] : "Project sources");
            if (!SourceExtensions.Contains(Path.GetExtension(path)))
            {
                items.Add(new() { Id = relative + "::metadata", Path = relative, Area = area, QualifiedName = Path.GetFileNameWithoutExtension(path),
                    Kind = "Task/project metadata", SourceHash = BuildEvidence.Hash(path), Role = "Non-PLC metadata; explicit disposition required" });
                fileRows.Add(new { path = relative, area, kind = "Metadata", declarations = 0 });
                continue;
            }
            var xml = XDocument.Load(path, LoadOptions.SetLineInfo | LoadOptions.PreserveWhitespace);
            var top = xml.Root?.Elements().Single(e => e.Name.LocalName is "POU" or "DUT" or "GVL" or "Itf") ?? throw new FormatException("Missing PLC object: " + relative);
            bool generated = top.Descendants("Declaration").Any(d => Regex.IsMatch(d.Value, @"\{\s*attribute\s+'TcGenerated'", RegexOptions.IgnoreCase));
            string role = generated ? "Generated source; explicit disposition required; do not hand-edit"
                : selectedArea?.Role ?? "Unclassified project source; explicit disposition required";
            int count = 0;
            foreach (var declaration in top.DescendantsAndSelf().Where(e => e.Name.LocalName == "Declaration"))
            {
                var node = declaration.Parent!;
                string qualified = string.Join('.', node.AncestorsAndSelf().Reverse().Where(e => e.Name.LocalName != "TcPlcObject" && e.Attribute("Name") != null).Select(e => e.Attribute("Name")!.Value));
                string kind = node.Name.LocalName;
                string id = relative + "::" + qualified + "[" + kind + "]";
                string? parent = node == top ? null : relative + "::" + string.Join('.', node.Parent!.AncestorsAndSelf().Reverse()
                    .Where(e => e.Name.LocalName != "TcPlcObject" && e.Attribute("Name") != null).Select(e => e.Attribute("Name")!.Value)) + "[" + node.Parent!.Name.LocalName + "]";
                AddDeclaration(items, declaration.Value, id, parent, relative, area, qualified, kind, role, BuildEvidence.Hash(path), XmlLine(declaration));
                var rootRow = items.Single(i => i.Id == id);
                if (kind == "GVL" && bool.TryParse(node.Attribute("ParameterList")?.Value, out bool parameterList) && parameterList)
                    items[items.IndexOf(rootRow)] = rootRow with { DeclarationForm = "Library parameter list" };
                count++;
            }
            fileRows.Add(new { path = relative, area, kind = top.Name.LocalName, generated, declarations = count });
        }
        items.Add(new() { Id = Relative(projectPath) + "::project", Path = Relative(projectPath), Area = "Project metadata", QualifiedName = Path.GetFileName(projectPath),
            Kind = "Project metadata", SourceHash = BuildEvidence.Hash(projectPath), Role = "Compile membership and library identity; explicit disposition required" });
        foreach (var reference in project.Descendants().Where(e => e.Name.LocalName is "PlaceholderReference" or "LibraryReference"))
        {
            string name = reference.Attribute("Include")?.Value ?? throw new FormatException("Unnamed library reference.");
            items.Add(new() { Id = Relative(projectPath) + "::" + reference.Name.LocalName + ":" + name, Path = Relative(projectPath), Area = "Project metadata",
                QualifiedName = name, Kind = "Library dependency", Parent = Relative(projectPath) + "::project", SourceHash = BuildEvidence.Hash(projectPath),
                Role = "External dependency; not a project-authored PLC declaration", Signature = Plain(reference.ToString()), Line = XmlLine(reference) });
        }
        string engineeringRoot = Path.GetDirectoryName(projectRoot)!;
        if (engineeringRoot.StartsWith(Path.GetFullPath(repo) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            foreach (var file in Directory.EnumerateFiles(engineeringRoot).Where(p => Path.GetExtension(p) is ".sln" or ".tsproj"))
            {
                evidence.Add(Relative(file), file);
                items.Add(new() { Id = Relative(file) + "::metadata", Path = Relative(file), Area = "Project metadata", QualifiedName = Path.GetFileName(file),
                    Kind = "Engineering metadata", SourceHash = BuildEvidence.Hash(file), Role = "Solution/system-project integration; explicit disposition required" });
            }
        if (items.Select(i => i.Id).Distinct(StringComparer.Ordinal).Count() != items.Count) throw new FormatException("Duplicate inventory identity.");
        evidence.Verify();
        Directory.CreateDirectory(output);
        HelpRenderer.Save(Path.Combine(output, "files.json"), fileRows);
        HelpRenderer.Save(Path.Combine(output, "items.json"), items);
        HelpRenderer.Save(Path.Combine(output, "input-hashes.json"), evidence.Hashes);
        SaveCsv(Path.Combine(output, "items.csv"), items);
        var unparsed = items.Where(i => i.Kind == "Unparsed declaration segment").ToList();
        HelpRenderer.Save(Path.Combine(output, "summary.json"), new {
            source = BuildEvidence.Git(repo), compileEntries = paths.Count, plcSourceFiles = paths.Count(p => SourceExtensions.Contains(Path.GetExtension(p))),
            objectsAndMembers = items.Count(i => i.Kind is "POU" or "DUT" or "GVL" or "Itf" or "Method" or "Property" or "Get" or "Set" or "Action" or "Transition"),
            items = items.Count, unparsedSegments = unparsed.Count,
            excludedDirectories = scope.ExcludedDirectories,
            area = items.GroupBy(i => i.Area).Select(g => new { area = g.Key, items = g.Count(), kinds = g.GroupBy(i => i.Kind).ToDictionary(k => k.Key, k => k.Count()) }),
            candidateFlags = items.SelectMany(i => i.CandidateFlags).GroupBy(f => f).ToDictionary(g => g.Key, g => g.Count()),
            preservedInputs = true, allReviewDimensionsOpen = true,
            limitation = "Saved-source membership and lexical enumeration only. Observations are review candidates, not format/content/native-display/rendering acceptance. Non-applicability requires an explicit reviewed decision."
        });
        Console.WriteLine($"Inventory: {paths.Count} Compile entries, {items.Count} rows, {unparsed.Count} unparsed segments. All review dimensions remain open.");
        if (unparsed.Count != 0) throw new FormatException("Inventory contains unresolved declaration segments; see items.json.");
    }

    internal static void AddDeclaration(List<InventoryItem> items, string text, string id, string? parent, string path, string area, string qualified, string kind, string role, string hash, int line)
    {
        var all = Parser.Lex(text); var code = Parser.Code(all);
        int firstHeader = code.FindIndex(t => Headers.Contains(t.Text));
        int firstBlock = code.FindIndex(t => VariableBlocks.Contains(t.Text));
        int headerEnd = firstBlock >= 0 ? firstBlock : code.Count;
        var header = code.Take(headerEnd).ToList();
        string visibility = header.FirstOrDefault(t => new[] { "PUBLIC", "PROTECTED", "PRIVATE", "INTERNAL" }.Contains(t.Text.ToUpperInvariant()))?.Text.ToUpperInvariant() ?? "Unspecified";
        int start = firstHeader >= 0 ? code[firstHeader].Start : firstBlock >= 0 ? code[firstBlock].Start : text.Length;
        var leading = all.Where(t => t.Kind == "comment" && t.End <= start).ToList();
        string marked = string.Join("\n", leading.Where(t => t.Text.StartsWith("//!") || t.Text.StartsWith("(*!")).Select(Comment));
        string ordinary = string.Join(" ", leading.Where(t => !t.Text.StartsWith("//!") && !t.Text.StartsWith("(*!")).Select(Comment));
        string form = marked.Length > 0 ? "TE-marked documentation" : ordinary.Length > 0 ? "Ordinary comments only" : "No leading purpose detected";
        string declarationForm = kind == "POU" ? header.FirstOrDefault(t => Headers.Contains(t.Text))?.Text ?? kind : kind;
        if (kind == "DUT") declarationForm = code.Any(t => Is(t, "STRUCT")) ? "Structure" : code.Any(t => Is(t, "UNION")) ? "Union"
            : code.Zip(code.Skip(1)).Any(pair => pair.First.Text == ":" && pair.Second.Text == "(") ? "Enumeration" : "Alias";
        if (kind == "GVL") declarationForm = code.Any(t => Is(t, "CONSTANT")) ? "Constant/mixed GVL; inspect blocks" : "Mutable GVL";
        List<string> flags = [];
        if (kind is not ("Get" or "Set") && marked.Length == 0) flags.Add("No TE-marked declaration purpose observed");
        if (marked.Length > 0 && !Regex.IsMatch(marked, @"<\s*(summary|description)\b|@(summary|description)\b")) flags.Add("TE marker without detected purpose markup");
        if (Regex.IsMatch(ordinary, @"<\s*(summary|description)\b")) flags.Add("XML documentation without TE marker");
        if (Regex.IsMatch(marked, @"<\s*/?\s*(remarks|para)\b")) flags.Add("Unverified TE1030 remarks/para markup");
        items.Add(new() { Id = id, Parent = parent, Path = path, Area = area, QualifiedName = qualified, Kind = kind,
            Role = role, SourceHash = hash, Visibility = visibility, Line = line, Signature = Slice(text, header), DeclarationForm = declarationForm, DocumentationForm = form, CandidateFlags = flags });
        var make = new Func<string, string, string, List<Token>, Token?, int, InventoryItem>((name, elementKind, direction, tokens, delimiter, boundary) => {
            string native = "";
            string nativeForm = "Not observed";
            if (tokens.Count > 0)
            {
                var end = delimiter != null && delimiter.Line == tokens[^1].Line ? delimiter : tokens[^1];
                int boundaryLine = all.LastOrDefault(t => t.Kind != "comment" && t.End <= boundary)?.Line ?? 0;
                var trailing = all.FirstOrDefault(t => t.Kind == "comment" && t.Start >= end.End && t.Line == end.Line);
                var preceding = all.Where(t => t.Kind == "comment" && t.Start >= boundary && t.End <= tokens[0].Start
                    && t.Line > boundaryLine && t.Line < tokens[0].Line && !Regex.IsMatch(Comment(t), @"^\s*<")).ToList();
                native = trailing != null ? Comment(trailing) : Plain(string.Join(" ", preceding.Select(Comment)));
                if (trailing != null || preceding.Count > 0)
                {
                    var observed = trailing ?? preceding[0];
                    nativeForm = (trailing == null ? "Leading " : "Trailing ") + (observed.Text.StartsWith("//!") || observed.Text.StartsWith("(*!") ? "TE-marked comment" : "ordinary comment");
                }
            }
            return new() { Id = id + "/" + direction + ":" + name, Parent = id, Path = path, Area = area, QualifiedName = qualified + "." + name,
                Kind = elementKind, Direction = direction, SourceHash = hash, Role = role, Visibility = visibility,
                NativeCommentForm = nativeForm, NamedParamMarkupObserved = Regex.IsMatch(marked, "<param\\s+name=[\"']" + Regex.Escape(name) + "[\"']", RegexOptions.IgnoreCase),
                Line = line + (tokens.FirstOrDefault()?.Line ?? 1) - 1, Signature = Slice(text, tokens), NativeComment = native,
                DocumentationForm = native.Length == 0 ? "No adjacent element comment detected" : "Adjacent element comment observed",
                CandidateFlags = native.Length == 0 ? ["No adjacent element comment observed; inspect markup/inheritance/role"] : [] };
        });
        if (kind is "Method" or "Property" || kind == "POU" && header.Any(t => Is(t, "FUNCTION")))
        {
            int colon = header.FindIndex(t => t.Text == ":");
            if (colon >= 0)
            {
                var type = header.Skip(colon + 1).ToList();
                var row = make(kind == "Property" ? "$value" : "$return", kind == "Property" ? "Property value" : "Return value", "Result", type, null, type.FirstOrDefault()?.Start ?? 0);
                items.Add(row with { DeclaredType = Slice(text, type) });
            }
        }
        int index = 0;
        while (index < code.Count)
        {
            string block = code[index].Text.ToUpperInvariant();
            if (VariableBlocks.Contains(block) || block is "STRUCT" or "UNION")
            {
                string end = block is "STRUCT" or "UNION" ? "END_" + block : "END_VAR";
                int boundary = code[index].End; index++;
                while (index < code.Count && new[] { "CONSTANT", "RETAIN", "PERSISTENT", "NON_RETAIN" }.Contains(code[index].Text.ToUpperInvariant())) { block += " " + code[index].Text.ToUpperInvariant(); boundary = code[index++].End; }
                int begin = index, depth = 0;
                for (; index < code.Count && !Is(code[index], end); index++)
                {
                    if (code[index].Text is "(" or "[") depth++;
                    if (code[index].Text is ")" or "]") depth--;
                    if (code[index].Text != ";" || depth != 0) continue;
                    AddField(items, make, code.GetRange(begin, index - begin), code[index], boundary, block, text);
                    boundary = code[index].End; begin = index + 1;
                }
                if (index >= code.Count) throw new FormatException("Unclosed inventory block: " + id + " / " + block);
                if (begin != index) AddUnparsed(items, id, path, area, qualified, hash, line, code.GetRange(begin, index - begin), text, block);
                index++; continue;
            }
            if (kind == "DUT" && code[index].Text == ":" && index + 1 < code.Count && code[index + 1].Text == "(")
            {
                int boundary = code[index + 1].End; index += 2;
                int begin = index, depth = 0;
                for (; index < code.Count; index++)
                {
                    if (depth == 0 && (code[index].Text is "," or ")"))
                    {
                        var part = code.GetRange(begin, index - begin);
                        if (part.Count > 0 && part[0].Kind == "word")
                        {
                            int assignment = part.FindIndex(t => t.Text == ":=");
                            items.Add(make(part[0].Text, "Enumerator", "ENUM", part, code[index], boundary) with {
                                DeclaredType = qualified, Initializer = assignment < 0 ? null : Slice(text, part.Skip(assignment + 1).ToList()) });
                        }
                        else if (part.Count > 0) AddUnparsed(items, id, path, area, qualified, hash, line, part, text, "ENUM");
                        boundary = code[index].End; begin = index + 1;
                        if (code[index].Text == ")") { index++; break; }
                    }
                    else if (code[index].Text is "(" or "[") depth++;
                    else if (code[index].Text is ")" or "]") depth--;
                }
                continue;
            }
            index++;
        }
    }

    static void AddField(List<InventoryItem> items, Func<string, string, string, List<Token>, Token?, int, InventoryItem> make,
        List<Token> part, Token delimiter, int boundary, string block, string text)
    {
        int colon = part.FindIndex(t => t.Text == ":");
        if (colon < 1) throw new FormatException("Unrecognized field declaration in inventory: " + Slice(text, part));
        var lhs = part.Take(colon).ToList();
        int at = lhs.FindIndex(t => Is(t, "AT"));
        if (at >= 0) lhs = lhs.Take(at).ToList();
        var names = lhs.Where(t => t.Kind == "word").Select(t => t.Text).ToList();
        if (names.Count == 0 || lhs.Any(t => t.Kind != "word" && t.Text != ",")) throw new FormatException("Unsupported inventory field names: " + Slice(text, part));
        int initial = part.FindIndex(t => t.Text == ":=");
        foreach (string name in names)
        {
            var row = make(name, block is "STRUCT" or "UNION" ? "DUT field" : "Variable/parameter", block, part, delimiter, boundary);
            items.Add(row with {
                Visibility = block.StartsWith("VAR", StringComparison.Ordinal) && !block.StartsWith("VAR_INPUT", StringComparison.Ordinal)
                    && !block.StartsWith("VAR_OUTPUT", StringComparison.Ordinal) && !block.StartsWith("VAR_IN_OUT", StringComparison.Ordinal)
                    && !block.StartsWith("VAR_GLOBAL", StringComparison.Ordinal) ? "Local/internal" : row.Visibility,
                DeclaredType = Slice(text, part.Skip(colon + 1).Take((initial < 0 ? part.Count : initial) - colon - 1).ToList()),
                Initializer = initial < 0 ? null : Slice(text, part.Skip(initial + 1).ToList()) });
        }
    }

    static void AddUnparsed(List<InventoryItem> items, string parent, string path, string area, string qualified, string hash, int line, List<Token> part, string text, string block)
    {
        items.Add(new() { Id = parent + "/unparsed:" + part[0].Start, Parent = parent, Path = path, Area = area, QualifiedName = qualified,
            Kind = "Unparsed declaration segment", SourceHash = hash, Line = line + part[0].Line - 1, Direction = block,
            Signature = Slice(text, part), CandidateFlags = ["Inventory grammar requires review"] });
    }

    static void SaveCsv(string path, List<InventoryItem> items)
    {
        static string Cell(string? value) => "\"" + (value ?? "").Replace("\"", "\"\"") + "\"";
        var csv = new StringBuilder("Id,SourceHash,Parent,Area,Path,QualifiedName,Kind,Visibility,Role,Line,Signature,Direction,DeclaredType,Initializer,DeclarationForm,DocumentationForm,NativeCommentForm,NamedParamMarkupObserved,NativeComment,Classification,FormatAndElements,Meaning,SavedSourcesAndOfflineChecks,NativeXae,Html,CandidateFlags\r\n");
        foreach (var i in items)
            csv.AppendLine(string.Join(',', new[] { i.Id,i.SourceHash,i.Parent,i.Area,i.Path,i.QualifiedName,i.Kind,i.Visibility,i.Role,i.Line.ToString(),i.Signature,i.Direction,i.DeclaredType,i.Initializer,i.DeclarationForm,i.DocumentationForm,i.NativeCommentForm,i.NamedParamMarkupObserved.ToString(),i.NativeComment,
                i.Review["classification"],i.Review["formatAndElements"],i.Review["meaning"],i.Review["savedSourcesAndOfflineChecks"],i.Review["nativeXae"],i.Review["html"],string.Join("; ",i.CandidateFlags) }.Select(Cell)));
        File.WriteAllText(path, csv.ToString().ReplaceLineEndings("\r\n"), new UTF8Encoding(true));
    }
}
