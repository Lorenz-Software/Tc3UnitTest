using System.Net;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace TwinCatDocumentation;

sealed record GuideDocument(string File, string Title, string Markdown, string Source, string Hash, List<string> ApiTypes)
{
    public string Html => Path.ChangeExtension(File, ".html");
}

static class GuidePresentation
{
    static string E(string text) => WebUtility.HtmlEncode(text);

    public static List<GuideDocument> Read(string repo, HelpGuide? guide, List<Api> apis)
    {
        if (guide == null) return [];
        string root = ProjectConfiguration.ConfinedPath(repo, guide.SourceRoot);
        var result = new List<GuideDocument>();
        foreach (var chapter in guide.Chapters)
        {
            string source = ProjectConfiguration.ConfinedPath(root, chapter.File);
            string markdown = System.IO.File.ReadAllText(source);
            var title = Regex.Match(markdown, @"\A# ([^\r\n]+)(?:\r?\n|$)");
            if (!title.Success) throw new FormatException("Guide chapter must start with one H1 title: " + chapter.File);
            if (apis.Any(a => string.Equals(a.Uid + ".html", Path.ChangeExtension(chapter.File, ".html"), StringComparison.OrdinalIgnoreCase)))
                throw new FormatException("Guide chapter collides with an API page: " + chapter.File);
            result.Add(new(chapter.File, title.Groups[1].Value.Trim(), markdown, source,
                Convert.ToHexString(SHA256.HashData(System.IO.File.ReadAllBytes(source))), chapter.ApiTypes));
        }
        return result;
    }

    public static string Plain(string markdown) => Regex.Replace(
        Regex.Replace(markdown, @"\[([^\]]+)\]\([^)]+\)", "$1"), @"[`#*|]|^\s*```[^\r\n]*", " ", RegexOptions.Multiline);

    public static void Stage(string output, HelpGuide guide, List<GuideDocument> documents, List<Api> apis)
    {
        HelpRenderer.SavePage(output, "guide", guide.Title,
            "<p class=\"page-kind\">Usage and extension</p><h1>" + E(guide.Title) + "</h1>"
            + "<p class=\"lead\">" + E(guide.Introduction ?? "Read these chapters in order, or choose the topic you need.") + "</p>"
            + "<p>The guide covers more of the framework than the selected API reference. Related API entries are linked where available; entries outside this export are marked explicitly.</p><ol class=\"guide-chapters\">"
            + string.Join("", documents.Select(d => $"<li><a href=\"{d.Html}\">{E(d.Title)}</a></li>")) + "</ol>");
        foreach (var document in documents)
        {
            string related = document.ApiTypes.Count == 0 ? "" : "\r\n\r\n## Related API reference\r\n\r\n"
                + string.Join("\r\n", document.ApiTypes.Select(name => apis.SingleOrDefault(a => a.Owner == null && a.Name == name) is { } api
                    ? $"- [{name}]({api.Uid}.yml)" : $"- `{name}` — not included in this API export."));
            System.IO.File.WriteAllText(Path.Combine(output, document.File), (document.Markdown + related + "\r\n").ReplaceLineEndings("\r\n"));
        }
        HelpRenderer.Save(Path.Combine(output, "guide-model.json"), documents.Select(d => new {
            file = d.File, title = d.Title, url = d.Html, source = d.Source, hash = d.Hash,
            text = Plain(d.Markdown), apiTypes = d.ApiTypes
        }));
    }

    public static string Related(Api api, List<GuideDocument> documents)
    {
        var related = documents.Where(d => d.ApiTypes.Contains(api.Owner ?? api.Name)).ToList();
        return related.Count == 0 ? "" : "<h2>Usage guide</h2><ul>" + string.Join("", related.Select(d =>
            $"<li><a href=\"{d.Html}\">{E(d.Title)}</a></li>")) + "</ul>";
    }
}
