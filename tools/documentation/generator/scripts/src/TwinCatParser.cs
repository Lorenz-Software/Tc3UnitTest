using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

static class Parser
{
    public static List<Token> Lex(string source)
    {
        List<Token> tokens = [];
        int i = 0, line = 1;
        while (i < source.Length)
        {
            if (char.IsWhiteSpace(source[i])) { if (source[i++] == '\n') line++; continue; }
            int start = i, tokenLine = line;
            string kind;
            if (source.AsSpan(i).StartsWith("//"))
            {
                kind = "comment";
                while (i < source.Length && source[i] != '\n') i++;
            }
            else if (source.AsSpan(i).StartsWith("(*"))
            {
                kind = "comment"; int depth = 1; i += 2;
                while (i < source.Length && depth > 0)
                {
                    if (source.AsSpan(i).StartsWith("(*")) { depth++; i += 2; }
                    else if (source.AsSpan(i).StartsWith("*)")) { depth--; i += 2; }
                    else { if (source[i++] == '\n') line++; }
                }
                if (depth != 0) throw new FormatException("Unterminated ST block comment.");
            }
            else if (source[i] is '\'' or '"')
            {
                kind = "string"; char quote = source[i++]; bool closed = false;
                while (i < source.Length)
                {
                    if (source[i] == '$' && i + 1 < source.Length) { i += 2; continue; }
                    if (source[i] == quote)
                    {
                        i++;
                        if (i < source.Length && source[i] == quote) { i++; continue; }
                        closed = true; break;
                    }
                    if (source[i++] == '\n') line++;
                }
                if (!closed) throw new FormatException("Unterminated ST string literal.");
            }
            else if (char.IsLetter(source[i]) || source[i] == '_')
            {
                kind = "word"; i++;
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_')) i++;
            }
            else if (source.AsSpan(i).StartsWith(":=")) { kind = "punctuation"; i += 2; }
            else { kind = "punctuation"; i++; }
            tokens.Add(new(source[start..i], kind, start, i, tokenLine));
        }
        return tokens;
    }

    static readonly HashSet<string> Headers = ["FUNCTION_BLOCK", "FUNCTION", "INTERFACE", "TYPE", "METHOD", "PROPERTY"];
    static readonly HashSet<string> Modifiers = ["PUBLIC", "PROTECTED", "PRIVATE", "INTERNAL", "ABSTRACT", "FINAL"];
    static bool Is(Token t, string text) => t.Text.Equals(text, StringComparison.OrdinalIgnoreCase);
    static string Plain(string text) => Regex.Replace(text, @"\s+", " ").Trim();
    static string Native(Token token) => token.Text.StartsWith("//!") ? token.Text[3..].Trim()
        : token.Text.StartsWith("//") ? token.Text[2..].TrimStart('/').Trim()
        : token.Text.StartsWith("(*!") ? token.Text[3..^2].Trim() : token.Text[2..^2].Trim();

    internal static List<Token> Code(List<Token> tokens)
    {
        List<Token> code = []; int braces = 0;
        foreach (var token in tokens)
        {
            if (token.Kind == "comment") continue;
            if (token.Text == "{") { braces++; continue; }
            if (token.Text == "}") { if (--braces < 0) throw new FormatException("Unbalanced attribute."); continue; }
            if (braces == 0) code.Add(token);
        }
        if (braces != 0) throw new FormatException("Unclosed attribute.");
        return code;
    }

    static string RenderXml(XNode node) => node switch
    {
        XText text => Plain(text.Value),
        XElement e when e.Name.LocalName == "para" => "\n\n" + string.Join(" ", e.Nodes().Select(RenderXml)).Trim() + "\n\n",
        XElement e when e.Name.LocalName == "code" => "\n\n```\n" + e.Value.Trim().ReplaceLineEndings("\n") + "\n```\n\n",
        XElement e when e.Name.LocalName == "c" => "`" + e.Value + "`",
        XElement e when e.Name.LocalName is "summary" or "remarks" or "description" or "param" or "returns" => string.Join(" ", e.Nodes().Select(RenderXml)).Trim(),
        XElement e => throw new FormatException("Unsupported documentation markup in probe: " + e.Name),
        _ => ""
    };

    static Docs ReadDocs(List<Token> all, int headerStart)
    {
        var leading = all.Where(t => t.Kind == "comment" && t.End <= headerStart).ToList();
        string xml = string.Join("\n", leading.Where(t => t.Text.StartsWith("//!") || t.Text.StartsWith("(*!"))
            .Select(t => t.Text.StartsWith("//!") ? t.Text[3..] : t.Text[3..^2]));
        if (xml.Length > 0)
        {
            var root = XElement.Parse("<doc>" + xml + "</doc>");
            foreach (var element in root.Elements()) _ = RenderXml(element);
            string Read(string name) => string.Join("\n\n", root.Elements(name).Select(RenderXml)).Trim();
            return new(Read("summary"), string.Join("\n\n", new[] { Read("remarks"), Read("description") }.Where(s => s.Length > 0)),
                root.Elements("param").ToDictionary(e => (string?)e.Attribute("name") ?? throw new FormatException("Unnamed param."), RenderXml), Read("returns"));
        }
        return new(Plain(string.Join(" ", leading.Select(Native))), "", [], "");
    }

    public static Api Parse(string name, string kind, string declaration, string source, string? owner = null, string libraryNamespace = "Library")
    {
        var all = Lex(declaration); var code = Code(all);
        int h = code.FindIndex(t => Headers.Contains(t.Text.ToUpperInvariant()));
        if (h < 0) throw new FormatException("No supported declaration header: " + name);
        int n = h + 1;
        while (n < code.Count && Modifiers.Contains(code[n].Text.ToUpperInvariant())) n++;
        if (n >= code.Count || code[n].Text != name) throw new FormatException("Object name/signature mismatch: " + name);
        int stop = code.FindIndex(n + 1, t => t.Text.StartsWith("VAR", StringComparison.OrdinalIgnoreCase) || Is(t, "STRUCT"));
        if (stop < 0) stop = code.Count;
        var header = code.GetRange(h, stop - h);
        if (kind == "DUT") return ParseData(name, declaration, source, libraryNamespace, all, code, h, n);
        string access = header.FirstOrDefault(t => t.Text.ToUpperInvariant() is "PUBLIC" or "PROTECTED" or "PRIVATE" or "INTERNAL")?.Text.ToUpperInvariant() ?? "PUBLIC";
        string? baseName = null;
        List<string> interfaces = [];
        for (int i = 0; i < header.Count; i++)
        {
            if (Is(header[i], "EXTENDS")) baseName = header.ElementAtOrDefault(i + 1)?.Text;
            if (Is(header[i], "IMPLEMENTS")) interfaces.AddRange(header.Skip(i + 1).Where(t => t.Kind == "word").Select(t => t.Text));
        }
        string? returnType = null;
        int colon = header.FindIndex(t => t.Text == ":");
        if (colon >= 0 && kind != "DUT") returnType = Plain(declaration[header[colon + 1].Start..header[^1].End]);
        string returnComment = NativeOrEmpty(all.FirstOrDefault(t => t.Kind == "comment" && t.Start >= header[^1].End && t.Line == header[^1].Line));
        var fields = ReadFields(name, declaration, all, code, stop);
        var docs = ReadDocs(all, code[h].Start);
        CheckDescriptions(name, docs, fields);
        string signature = Plain(declaration[header[0].Start..header[^1].End]);
        return new Api { Name = name, Uid = libraryNamespace + "." + (owner == null ? "" : owner + ".") + name, Kind = kind,
            Source = source, Owner = owner, Access = access, Base = baseName, Interfaces = interfaces, ReturnType = returnType,
            ReturnComment = returnComment, Signature = signature, Docs = docs, Fields = fields,
            Declaration = CleanDeclaration(declaration) };
    }

    static List<Field> ReadFields(string name, string declaration, List<Token> all, List<Token> code, int stop)
    {
        List<Field> fields = [];
        for (int i = stop; i < code.Count; i++)
        {
            string block = code[i].Text.ToUpperInvariant();
            if (block is not ("VAR_INPUT" or "VAR_OUTPUT" or "VAR_IN_OUT" or "VAR_GLOBAL" or "STRUCT" or "UNION")) continue;
            string end = block is "STRUCT" or "UNION" ? "END_" + block : "END_VAR";
            i++;
            if (i < code.Count && Is(code[i], "CONSTANT")) { block += " CONSTANT"; i++; }
            int declarationStart = i;
            for (; i < code.Count && !Is(code[i], end); i++)
            {
                if (code[i].Text != ";") continue;
                var part = code.GetRange(declarationStart, i - declarationStart);
                int separator = part.FindIndex(t => t.Text == ":");
                if (separator != 1 || part[0].Kind != "word") throw new FormatException("Unsupported field declaration: " + name);
                int initial = part.FindIndex(t => t.Text == ":=");
                int typeEnd = initial >= 0 ? initial : part.Count;
                string type = Plain(declaration[part[separator + 1].Start..part[typeEnd - 1].End]);
                string? value = initial >= 0 ? Plain(declaration[part[initial + 1].Start..part[^1].End]) : null;
                Token? trailing = all.FirstOrDefault(t => t.Kind == "comment" && t.Start >= code[i].End && t.Line == code[i].Line);
                int boundary = declarationStart > 0 ? code[declarationStart - 1].End : 0;
                var before = all.Where(t => t.Kind == "comment" && t.Start >= boundary && t.End <= part[0].Start && !t.Text.StartsWith("//!")
                    && t.Line > code[declarationStart - 1].Line).ToList();
                string comment = trailing != null ? Native(trailing) : Plain(string.Join(" ", before.Select(Native)));
                fields.Add(new(part[0].Text, type, value, comment, block));
                declarationStart = i + 1;
            }
            if (i >= code.Count) throw new FormatException("Unclosed field block: " + name);
            if (declarationStart != i) throw new FormatException("Unterminated field declaration: " + name);
        }
        if (fields.Select(f => f.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != fields.Count)
            throw new FormatException("Duplicate field declaration: " + name);
        return fields;
    }

    static void CheckDescriptions(string name, Docs docs, List<Field> fields)
    {
        foreach (var field in fields)
            if (docs.Parameters.TryGetValue(field.Name, out string? markup) && field.Comment.Length > 0 && Plain(markup) != Plain(field.Comment))
                throw new FormatException("Conflicting native/param documentation: " + name + "." + field.Name);
    }

    internal static Api ParseConstants(string name, string declaration, string source, string libraryNamespace, bool parameterList)
    {
        var all = Lex(declaration); var code = Code(all);
        if (code.Count < 3 || !Is(code[0], "VAR_GLOBAL") || !Is(code[^1], "END_VAR")
            || code.Count(t => Is(t, "VAR_GLOBAL")) != 1)
            throw new FormatException("Only a single VAR_GLOBAL block is supported: " + name);
        var fields = ReadFields(name, declaration, all, code, 0);
        if (fields.Count == 0 || (Is(code[1], "CONSTANT") && fields.Any(f => f.Default == null)))
            throw new FormatException("Constant lists require explicit initializers: " + name);
        var docs = ReadDocs(all, code[0].Start);
        CheckDescriptions(name, docs, fields);
        return new Api { Name = name, Uid = libraryNamespace + "." + name, Kind = "GVL", Source = source,
            Access = "PUBLIC", Signature = Is(code[1], "CONSTANT") ? "VAR_GLOBAL CONSTANT" : "VAR_GLOBAL", Docs = docs, Fields = fields, IsParameterList = parameterList,
            Declaration = CleanDeclaration(declaration) };
    }

    internal static string CleanDeclaration(string declaration)
    {
        // Reconstruct only exported declarations separately; this retains exact datatype
        // syntax without copying local variables or implementation attributes.
        var tokens = Code(Lex(declaration));
        var result = new StringBuilder(); int previous = 0;
        foreach (var t in tokens) {
            if (result.Length > 0) result.Append(declaration[previous..t.Start].Contains('\n') ? "\n" : " ");
            result.Append(t.Text); previous = t.End;
        }
        return result.ToString();
    }

    static Api ParseData(string name, string declaration, string source, string ns, List<Token> all, List<Token> code, int h, int n)
    {
        if (n + 2 >= code.Count || code[n + 1].Text != ":" || !Is(code[^1], "END_TYPE"))
            throw new FormatException("Unsupported datatype header: " + name);
        int start = n + 2;
        string form = Is(code[start], "STRUCT") ? "Structure" : Is(code[start], "UNION") ? "Union" : code[start].Text == "(" ? "Enumeration" : "Alias";
        List<Field> fields = [];
        string? alias = null, underlying = null, typeDefault = null;
        if (form is "Structure" or "Union") fields = ReadFields(name, declaration, all, code, start);
        else if (form == "Enumeration")
        {
            int end = code.FindIndex(start + 1, t => t.Text == ")");
            if (end < 0) throw new FormatException("Unclosed enumeration: " + name);
            int initial = code.FindIndex(end + 1, t => t.Text == ":=");
            int semicolon = code.FindIndex(end + 1, t => t.Text == ";");
            if (semicolon < 0) throw new FormatException("Missing enum terminator: " + name);
            int lastType = initial >= 0 ? initial : semicolon;
            if (lastType > end + 1) underlying = Plain(declaration[code[end + 1].Start..code[lastType - 1].End]);
            if (initial >= 0) typeDefault = Plain(declaration[code[initial + 1].Start..code[semicolon - 1].End]);
            int first = start + 1;
            for (int i = first; i <= end; i++)
            {
                if (i != end && code[i].Text != ",") continue;
                var part = code.GetRange(first, i - first);
                if (part.Count == 0 || part[0].Kind != "word" || (part.Count > 1 && (part.Count < 3 || part[1].Text != ":=")))
                    throw new FormatException("Unsupported enumerator: " + name);
                var trailing = all.FirstOrDefault(t => t.Kind == "comment" && t.Start >= (i == end ? part[^1].End : code[i].End) && t.Line == part[^1].Line);
                string? value = part.Count > 1 ? Plain(declaration[part[2].Start..part[^1].End]) : null;
                fields.Add(new(part[0].Text, name, value, NativeOrEmpty(trailing), "ENUM"));
                first = i + 1;
            }
        }
        else {
            alias = Plain(declaration[code[start].Start..code[^2].End]).TrimEnd(';').Trim();
            if (!Regex.IsMatch(alias, @"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$"))
                throw new FormatException("Only simple referenced-type aliases are supported: " + name);
        }
        var docs = ReadDocs(all, code[h].Start); CheckDescriptions(name, docs, fields);
        string access = code.Take(n).FirstOrDefault(t => Modifiers.Contains(t.Text.ToUpperInvariant()))?.Text.ToUpperInvariant() ?? "PUBLIC";
        return new Api { Name = name, Uid = ns + "." + name, Kind = "DUT", Source = source, Access = access,
            Signature = Plain(declaration[code[h].Start..code[n + 1].End]) + " " + (form is "Structure" or "Union" ? code[start].Text : form == "Enumeration" ? "(...)" : Plain(declaration[code[start].Start..code[^2].End])),
            DataKind = form, AliasType = alias, UnderlyingType = underlying, TypeDefault = typeDefault, Docs = docs, Fields = fields, Declaration = CleanDeclaration(declaration) };
    }

    static string NativeOrEmpty(Token? token) => token == null ? "" : Native(token);

    public static List<Api> Read(string path, string repo, string libraryNamespace)
    {
        var root = XDocument.Load(path).Root ?? throw new FormatException("Missing XML root.");
        var type = root.Elements().Single(e => e.Name.LocalName is "POU" or "Itf" or "DUT" or "GVL");
        string name = (string?)type.Attribute("Name") ?? throw new FormatException("Missing object name.");
        string source = Path.GetRelativePath(repo, path).Replace('\\', '/');
        if (type.Name.LocalName == "GVL")
        {
            bool parameterList = false;
            if (type.Attribute("ParameterList") is { } attribute && !bool.TryParse(attribute.Value, out parameterList))
                throw new FormatException("Invalid ParameterList attribute: " + name);
            return [ParseConstants(name, type.Element("Declaration")?.Value ?? "", source, libraryNamespace, parameterList)];
        }
        List<Api> result = [Parse(name, type.Name.LocalName, type.Element("Declaration")?.Value ?? "", source, libraryNamespace: libraryNamespace)];
        foreach (var member in type.Elements().Where(e => e.Name.LocalName is "Method" or "Property"))
        {
            var item = Parse((string)member.Attribute("Name")!, member.Name.LocalName, member.Element("Declaration")?.Value ?? "", source, name, libraryNamespace);
            if (item.Access is "PUBLIC" or "PROTECTED") {
                item.Accessors.AddRange(member.Elements().Where(e => e.Name.LocalName is "Get" or "Set")
                    .Where(e => !Code(Lex(e.Element("Declaration")?.Value ?? "")).Any(t => Is(t, "PRIVATE") || Is(t, "INTERNAL")))
                    .Select(e => e.Name.LocalName));
                result.Add(item);
            }
        }
        return result;
    }
}
