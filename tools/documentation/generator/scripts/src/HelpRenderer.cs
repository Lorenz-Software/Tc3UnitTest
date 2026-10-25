using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

static class HelpRenderer
{
    internal static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    internal static void Save(string path, object value) => File.WriteAllText(path, JsonSerializer.Serialize(value, JsonOptions).ReplaceLineEndings("\r\n"));
    static string FileName(Api item) => item.Uid + ".yml";
    static string HtmlName(Api item) => item.Uid + ".html";
    static string Escape(string value) => System.Net.WebUtility.HtmlEncode(value);


    public static List<Api> Effective(Api type, List<Api> apis, HashSet<string>? seen = null)
    {
        seen ??= [];
        if (!seen.Add(type.Uid)) throw new FormatException("Inheritance cycle at " + type.Name);
        var own = apis.Where(a => a.Owner == type.Name).ToList();
        if (type.Base != null)
        {
            var parent = apis.SingleOrDefault(a => a.Owner == null && a.Name == type.Base) ?? throw new FormatException("Unresolved base in selected API: " + type.Base);
            own.AddRange(Effective(parent, apis, seen).Where(a => !own.Any(o => o.Kind == a.Kind && o.Name == a.Name)));
        }
        return own;
    }

    internal static void SavePage(string output, string name, string title, string html) =>
        File.WriteAllText(Path.Combine(output, name + ".yml"), "#YamlMime:ApiPage\r\n" +
            JsonSerializer.Serialize(new { title, body = new[] { new { markdown = html } } }, JsonOptions).ReplaceLineEndings("\r\n"));

    public static void Render(List<Api> apis, ProjectConfiguration config, string output, string theme, string stylesheet, string licenseFile, string? logoFile, string? headerLogoFile, List<GuideDocument> guide, LibraryMetadata? metadata, SourceIdentity identity)
    {
        string? logoName = logoFile == null ? null : "author-logo" + Path.GetExtension(logoFile).ToLowerInvariant();
        string? headerLogoName = headerLogoFile == null ? null : "author-symbol" + Path.GetExtension(headerLogoFile).ToLowerInvariant();
        string[] resources = ["help-search.js", "help-project.css", "help-build.json", "LICENSE.txt", .. new[] { logoName, headerLogoName }.OfType<string>()];
        if (headerLogoFile != null) File.Copy(headerLogoFile, Path.Combine(output, headerLogoName!), true);
        if (logoFile != null) File.Copy(logoFile, Path.Combine(output, logoName!), true);
        Save(Path.Combine(output, "help-resources.json"), resources);
        foreach (var api in apis) SavePage(output, api.Uid, api.Name, ApiPresentation.Page(api, apis, config) + GuidePresentation.Related(api, guide));
        SavePage(output, "index", config.Overview.Title, ApiPresentation.Overview(apis, config));
        SavePage(output, "catalog", "API catalog", ApiPresentation.Catalog(apis, config));
        SavePage(output, "about", "About and license", ApiPresentation.About(config, File.ReadAllText(licenseFile), logoName, metadata, identity));
        Save(Path.Combine(output, "api-model.json"), apis);
        if (config.Guide != null) GuidePresentation.Stage(output, config.Guide, guide, apis);
        var guidePages = config.Guide == null ? Array.Empty<string>() : guide.Select(d => d.Html).Prepend("guide.html").ToArray();
        Save(Path.Combine(output, "help-pages.json"), apis.Select(HtmlName).Prepend("about.html").Prepend("catalog.html").Prepend("index.html").Concat(guidePages));
        var navigation = new StringBuilder("<h2 class=\"nav-label\">Documentation</h2><a class=\"overview-link\" href=\"index.html\">Overview</a>");
        if (config.Guide != null)
            navigation.Append("<details class=\"guide-navigation\"><summary><a class=\"overview-link\" href=\"guide.html\">" + Escape(config.Guide.Title) + "</a></summary><div class=\"guide-chapter-links\">"
                + string.Join("", guide.Select(d => $"<a href=\"{d.Html}\">{Escape(d.Title)}</a>")) + "</div></details>");
        navigation.Append("<a class=\"overview-link\" href=\"catalog.html\">API catalog</a><h2 class=\"nav-label\">Areas</h2>");
        foreach (var (group, i) in config.Groups.Select((g, i) => (g, i)))
            navigation.Append($"<a class=\"overview-link\" href=\"catalog.html?group={i}\">{Escape(group.Title)}<span class=\"nav-count\">{group.Types.Count}</span></a>");
        navigation.Append("<h2 class=\"nav-label\">Element types</h2>");
        foreach (var category in apis.Where(a => a.Owner == null).GroupBy(ElementPresentation.Category).OrderBy(g => ElementPresentation.CategoryOrder(g.Key)))
            navigation.Append($"<a class=\"overview-link type-nav\" href=\"catalog.html?category={category.Key}\">{ElementPresentation.CategoryIcon(category.Key)}{Escape(ElementPresentation.CategoryLabel(category.Key))}<span class=\"nav-count\">{category.Count()}</span></a>");
        navigation.Append("<section id=\"context-navigation\" hidden aria-label=\"Current element\"></section>");
        var search = apis.Select(a => new { name = a.Owner == null ? a.Name : a.Owner + "." + a.Name, url = HtmlName(a), kind = ElementPresentation.Label(a),
            owner = a.Owner == null ? null : HtmlName(apis.Single(t => t.Owner == null && t.Name == a.Owner)),
            group = config.Groups.FindIndex(g => g.Types.Contains(a.Owner ?? a.Name)),
            text = string.Join(" ", new[] { a.Docs.Summary, a.Docs.Remarks, a.Docs.Returns, a.ReturnComment }.Concat(a.Fields.Select(f => f.Name + " " + f.Type + " " + f.Default + " " + f.Comment))) })
            .Concat(guide.Select(d => new { name = d.Title, url = d.Html, kind = "Guide", owner = (string?)null, group = -1, text = GuidePresentation.Plain(d.Markdown) }));
        File.WriteAllText(Path.Combine(output, "help-search.js"), "window.LIBRARY_HELP_SEARCH = " + JsonSerializer.Serialize(search) + ";\r\n");
        File.Copy(licenseFile, Path.Combine(output, "LICENSE.txt"), true);
        File.Copy(stylesheet, Path.Combine(output, "help-project.css"), true);
        Save(Path.Combine(output, "docfx.json"), new { build = new {
            content = new[] { new { files = apis.Select(FileName).Prepend("about.yml").Prepend("catalog.yml").Prepend("index.yml")
                .Concat(config.Guide == null ? [] : guide.Select(d => d.File).Prepend("guide.yml")).ToArray() } },
            resource = new[] { new { files = resources } }, dest = "site", template = new[] { theme },
            globalMetadata = new Dictionary<string, object> {
                ["_helpProduct"] = config.Product, ["_helpPublisher"] = config.Publisher!,
                ["_helpVersion"] = metadata?.Version ?? "",
                ["_helpBrandMark"] = config.BrandMark, ["_helpSubtitle"] = config.Subtitle,
                ["_helpCopyright"] = config.Attribution.Copyright,
                ["_helpHeaderLogo"] = headerLogoName ?? "",
                ["_helpAuthor"] = config.Attribution.Author,
                ["_helpEdition"] = config.Edition, ["_helpNavigation"] = navigation.ToString()
            }, disableGitFeatures = true } });
    }
}
