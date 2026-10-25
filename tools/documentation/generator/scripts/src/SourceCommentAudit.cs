using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

sealed record CommentAuditPolicy(string Region, List<string> ReviewedMarkup);
sealed record CommentFinding(string Id, string Path, string Area, string SourceHash, string Category, string Code, string Message);

// Source-layout evidence is independent of the HTML parser's legacy fallbacks.
static class SourceCommentAudit
{
    static readonly HashSet<string> Headers = new(StringComparer.OrdinalIgnoreCase) {
        "FUNCTION_BLOCK", "FUNCTION", "PROGRAM", "INTERFACE", "TYPE", "METHOD", "PROPERTY", "VAR_GLOBAL"
    };
    static bool Marked(Token t) => t.Text.StartsWith("//!") || t.Text.StartsWith("(*!");
    static string Body(Token t) => t.Text.StartsWith("//!") ? t.Text[3..] : t.Text[3..^2];

    internal static List<(string Code, string Message)> CheckHeader(string text, CommentAuditPolicy policy)
    {
        var all = Parser.Lex(text); var code = Parser.Code(all);
        int header = code.FindIndex(t => Headers.Contains(t.Text));
        if (header < 0) throw new FormatException("No supported documentation target header.");
        int start = code[header].Start;
        var docs = all.Where(t => t.Kind == "comment" && t.End <= start && Marked(t)).ToList();
        List<(string, string)> findings = [];
        if (docs.Count != 1 || !docs[0].Text.StartsWith("(*!"))
            findings.Add(("header-block", "Use one TE1030 block-comment header; line-comment headers do not satisfy this project's layout."));
        // Lexed braces cannot be confused with region text inside a string/comment.
        var pragmas = new List<(int Start, int End, List<Token> Tokens)>();
        for (int i = 0; i < all.Count; i++)
        {
            if (all[i].Text != "{") continue;
            int begin = i;
            while (i < all.Count && all[i].Text != "}") i++;
            if (i >= all.Count) throw new FormatException("Unclosed pragma.");
            pragmas.Add((all[begin].Start, all[i].End, all.GetRange(begin + 1, i - begin - 1)));
        }
        var regions = pragmas.Where(p => p.Tokens.Count == 2 && p.Tokens[0].Text.Equals("region", StringComparison.OrdinalIgnoreCase)
            && p.Tokens[1].Kind == "string" && p.Tokens[1].Text[1..^1] == policy.Region).ToList();
        var closes = pragmas.Where(p => p.Tokens.Count == 1 && p.Tokens[0].Text.Equals("endregion", StringComparison.OrdinalIgnoreCase)).ToList();
        bool enclosed = false;
        if (docs.Count == 1 && regions.Count == 1)
        {
            var open = regions[0];
            var close = closes.FirstOrDefault(p => p.Start > open.End);
            enclosed = open.End <= docs[0].Start && close.Start >= docs[0].End && close.End <= start;
            // The region contains only the documentation comment and whitespace.
            if (enclosed) enclosed = string.IsNullOrWhiteSpace(text[open.End..docs[0].Start])
                && string.IsNullOrWhiteSpace(text[docs[0].End..close.Start]);
        }
        if (!enclosed) findings.Add(("documentation-region", $"Enclose only the block header in one named {policy.Region} region before the declaration signature."));
        if (docs.Count == 0)
            findings.Add(("purpose", "No TE-marked declaration purpose; ordinary comment fallback is not source conformance."));
        else
        {
            try
            {
                var xml = XElement.Parse("<doc>" + string.Join("\n", docs.Select(Body)) + "</doc>");
                if (!xml.Elements().Any(e => e.Name.LocalName is "summary" or "description" && !string.IsNullOrWhiteSpace(e.Value)))
                    findings.Add(("purpose", "A nonempty summary or description is required."));
                foreach (var element in xml.Descendants())
                    if (!policy.ReviewedMarkup.Contains(element.Name.LocalName, StringComparer.Ordinal) || element.Name.NamespaceName.Length > 0)
                        findings.Add(("markup-review", "Markup outside the reviewed source profile: " + element.Name + ". Resolve it explicitly rather than accepting the HTML fallback."));
                foreach (var group in xml.Elements().Where(e => e.Name.LocalName is "summary" or "description").GroupBy(e => e.Name.LocalName))
                    if (group.Count() > 1) findings.Add(("duplicate-markup", "Repeated " + group.Key + " section."));
                foreach (var param in xml.Elements("param"))
                    if (string.IsNullOrWhiteSpace(param.Attribute("name")?.Value) || string.IsNullOrWhiteSpace(param.Value))
                        findings.Add(("param", "Named parameter markup requires a name and useful text."));
            }
            catch (System.Xml.XmlException error) { findings.Add(("documentation-xml", error.Message)); }
        }
        return findings.Distinct().ToList();
    }

    public static void Run(string repo, string inventory, string output, string policyPath)
    {
        var policy = JsonSerializer.Deserialize<CommentAuditPolicy>(File.ReadAllText(policyPath), new JsonSerializerOptions {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase, RespectRequiredConstructorParameters = true,
            UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
        }) ?? throw new FormatException("Missing source comment policy.");
        if (string.IsNullOrWhiteSpace(policy.Region) || policy.ReviewedMarkup.Count == 0) throw new FormatException("Incomplete source comment policy.");
        string ledgerPath = Path.Combine(inventory, "items.json");
        var items = JsonSerializer.Deserialize<List<InventoryItem>>(File.ReadAllText(ledgerPath)) ?? throw new FormatException("Missing ledger.");
        var byId = items.ToDictionary(i => i.Id, StringComparer.Ordinal);
        var evidence = new BuildEvidence(); evidence.Add("ledger", ledgerPath); evidence.Add("policy", policyPath);
        List<CommentFinding> findings = []; var dispositions = new List<object>();
        void Finding(InventoryItem row, string category, string code, string message) => findings.Add(new(row.Id, row.Path, row.Area, row.SourceHash, category, code, message));
        foreach (var file in items.GroupBy(i => i.Path))
        {
            string source = ProjectConfiguration.ConfinedPath(repo, file.Key);
            string hash = BuildEvidence.Hash(source);
            if (file.Any(i => i.SourceHash != hash)) throw new IOException("Stale review ledger: " + file.Key);
            evidence.Add(file.Key, source);
            var extension = Path.GetExtension(source);
            if (extension is not (".TcPOU" or ".TcIO" or ".TcDUT" or ".TcGVL"))
            {
                foreach (var row in file) dispositions.Add(new { row.Id, row.Path, row.SourceHash, category = row.Kind,
                    rule = "Metadata/dependency: no source documentation header; retain membership/identity/integration checks, with substantive acceptance open." });
                continue;
            }
            var xml = XDocument.Load(source);
            bool generated = xml.Descendants("Declaration").Any(d => Regex.IsMatch(d.Value, @"\{\s*attribute\s+'TcGenerated'", RegexOptions.IgnoreCase));
            if (generated)
            {
                foreach (var row in file) dispositions.Add(new { row.Id, row.Path, row.SourceHash, category = "Generated source",
                    rule = "TcGenerated provenance: header/element layout belongs to XAE; do not hand-edit. Verify library metadata consistency separately." });
                continue;
            }
            foreach (var declaration in xml.Descendants("Declaration"))
            {
                var node = declaration.Parent!;
                string name = string.Join('.', node.AncestorsAndSelf().Reverse().Where(e => e.Name.LocalName != "TcPlcObject" && e.Attribute("Name") != null).Select(e => e.Attribute("Name")!.Value));
                string id = file.Key + "::" + name + "[" + node.Name.LocalName + "]";
                if (!byId.TryGetValue(id, out var row)) throw new FormatException("Declaration missing from ledger: " + id);
                if (row.Kind is "Get" or "Set")
                {
                    if (row.Parent == null || !byId.TryGetValue(row.Parent, out var parent) || parent.Kind != "Property") throw new FormatException("Accessor has no property owner: " + id);
                    dispositions.Add(new { row.Id, row.Path, row.SourceHash, category = "Property accessor", rule = "Purpose is documented on parent " + row.Parent + "; review accessor-specific behavior separately. No duplicate header required." });
                    if (!Parser.Lex(declaration.Value).Any(t => t.Kind == "comment" && Marked(t))) continue;
                    // An accessor with its own header is an explicit review case, not an automatic pass.
                    Finding(row, "Review", "accessor-header", "Reconcile accessor-specific documentation with the parent property; avoid duplicate purpose text.");
                    continue;
                }
                foreach (var issue in CheckHeader(declaration.Value, policy)) Finding(row, "Format", issue.Code, issue.Message);
                if (Regex.IsMatch(row.Signature, @"\b(EXTENDS|IMPLEMENTS)\b", RegexOptions.IgnoreCase))
                    dispositions.Add(new { row.Id, row.Path, row.SourceHash, category = "Declared relationship", rule = "Review inherited/interface obligations from: " + row.Signature + ". This does not establish inherited documentation correctness." });
            }
            foreach (var row in file.Where(i => i.Kind is "Variable/parameter" or "DUT field" or "Enumerator" or "Return value" or "Property value"))
            {
                if (row.Visibility == "Local/internal")
                {
                    dispositions.Add(new { row.Id, row.Path, row.SourceHash, category = "Local implementation element", rule = "Proportionate relevance review; no mandatory filler comment. Existing source documentation must still be meaningful." });
                    continue;
                }
                if (row.NativeCommentForm.Contains("ordinary comment", StringComparison.Ordinal))
                    Finding(row, "Format", "native-marker", "Existing element description uses an ordinary comment; reconcile and use TE-marked element documentation.");
                else if (row.NativeComment.Length == 0)
                    Finding(row, "Review", "element-description", row.NamedParamMarkupObserved ? "Named param markup observed; reconcile native use and avoid duplicate text." : "Assess element meaning, role and inherited/parent description; no adjacent text detected.");
            }
        }
        evidence.Verify(); Directory.CreateDirectory(output);
        HelpRenderer.Save(Path.Combine(output, "findings.json"), findings);
        HelpRenderer.Save(Path.Combine(output, "dispositions.json"), dispositions);
        HelpRenderer.Save(Path.Combine(output, "input-hashes.json"), evidence.Hashes);
        HelpRenderer.Save(Path.Combine(output, "summary.json"), new {
            items = items.Count, findings = findings.Count,
            formatFindings = findings.Count(f => f.Category == "Format"), relevanceFindings = findings.Count(f => f.Category == "Review"),
            dispositions = dispositions.Count, area = findings.GroupBy(f => f.Area).Select(g => new { area = g.Key, findings = g.Count() }),
            categories = findings.GroupBy(f => f.Code).ToDictionary(g => g.Key, g => g.Count()),
            acceptance = "No semantic, native-display or complete-rendering acceptance. Dispositions describe review treatment, not verified behavior. Unknown markup requires explicit review, not a claim that TE1030 rejects it."
        });
        Console.WriteLine($"Source comment audit: {findings.Count(f => f.Category == "Format")} format findings; {findings.Count(f => f.Category == "Review")} relevance review findings. No acceptance implied.");
        if (findings.Count > 0) throw new FormatException("Source documentation findings remain open; see the audit report.");
    }
}
