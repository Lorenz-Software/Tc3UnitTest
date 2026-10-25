using System.Net;
using System.Text;

namespace TwinCatDocumentation;

// Presentation only: API semantics and project category membership arrive separately.
static class ApiPresentation
{
    static string E(string text) => WebUtility.HtmlEncode(text);
    static string Preformatted(string text) => E(text).Replace("\r\n", "\n").Replace("\n", "&#10;");
    static string Kind(Api api) => ElementPresentation.Label(api);
    static string Href(Api api) => api.Uid + ".html";
    static string Link(Api api, string? label = null) => $"<a href=\"{Href(api)}\">{E(label ?? api.Name)}</a>";
    internal static string Paragraphs(string text)
    {
        var html = new StringBuilder();
        foreach (var part in System.Text.RegularExpressions.Regex.Split(text, @"(```[\s\S]*?```)").Where(p => p.Length > 0))
        {
            if (part.StartsWith("```")) html.Append("<pre><code>" + Preformatted(part[3..^3].Trim('\n')) + "</code></pre>");
            else foreach (var paragraph in part.Split("\n\n", StringSplitOptions.RemoveEmptyEntries))
                html.Append("<p>" + System.Text.RegularExpressions.Regex.Replace(E(paragraph.Trim()), "`([^`]+)`", "<code>$1</code>") + "</p>");
        }
        return html.ToString();
    }
    static Api Type(string name, List<Api> apis) => apis.Single(a => a.Owner == null && a.Name == name);
    static string TypeName(string name, List<Api> apis)
    {
        if (apis.SingleOrDefault(a => a.Owner == null && a.Name == name) is { } api) return Link(api);
        var result = new StringBuilder(); int end = 0;
        foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(name, @"\b([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?\b"))
        {
            result.Append(E(name[end..match.Index]));
            var target = apis.SingleOrDefault(a => a.Owner == null && a.Name == match.Groups[1].Value);
            bool field = match.Groups[2].Success && target?.Fields.Any(f => f.Name == match.Groups[2].Value) == true;
            result.Append(target == null || (match.Groups[2].Success && !field) ? E(match.Value) : $"<a href=\"{Href(target)}{(field ? "#field-" + match.Groups[2].Value : "")}\">{E(match.Value)}</a>");
            end = match.Index + match.Length;
        }
        return result.Append(E(name[end..])).ToString();
    }
    static string GroupLink(int index, string title) => $"<a href=\"catalog.html?group={index}\">{E(title)}</a>";
    static string Table(string headings, string rows, string classes = "api-table") => $"<div class=\"table-scroll\"><table class=\"{classes}\"><thead><tr>{headings}</tr></thead><tbody>{rows}</tbody></table></div>";

    public static string About(ProjectConfiguration config, string license, string? logoName, LibraryMetadata? metadata, SourceIdentity sourceIdentity)
    {
        var attribution = config.Attribution;
        string logo = logoName == null ? "" : $"<img class=\"author-logo\" src=\"{E(logoName)}\" alt=\"{E(attribution.Author)}\">";
        string website = attribution.Website == null ? "" : $"<a class=\"author-website\" href=\"{E(attribution.Website)}\" target=\"_blank\" rel=\"noopener noreferrer\">{E(new Uri(attribution.Website).Host)} ↗</a>";
        if (logo.Length > 0 && attribution.Website != null)
            logo = $"<a class=\"author-logo-link\" href=\"{E(attribution.Website)}\" target=\"_blank\" rel=\"noopener noreferrer\">{logo}</a>";
        string identity = logo.Length == 0 && website.Length == 0 ? "" : $"<div class=\"author-identity\">{logo}<div><p class=\"page-kind\">Library author</p><h3>{E(attribution.Author)}</h3>{website}</div></div>";
        return $"<p class=\"page-kind\">Project information</p><h1>About and license</h1><p class=\"lead\">{E(config.Product)} · {E(config.Edition)}</p>"
            + LibraryInformation(metadata, sourceIdentity)
            + "<h2>Author and contact</h2>" + identity
            + Table("<th scope=\"col\">Item</th><th scope=\"col\">Details</th>",
                $"<tr><td>Author</td><td>{E(attribution.Author)}</td></tr><tr><td>Publisher</td><td>{E(config.Publisher!)}</td></tr>"
                + $"<tr><td>Contact</td><td><a href=\"mailto:{E(attribution.ContactEmail)}\">{E(attribution.ContactEmail)}</a></td></tr>"
                + $"<tr><td>Copyright</td><td>{E(attribution.Copyright)}</td></tr><tr><td>License</td><td>{E(attribution.LicenseName)}</td></tr>")
            + $"<h2>{E(attribution.LicenseName)}</h2><p>The project license is reproduced below and included in this help package as <a href=\"LICENSE.txt\">LICENSE.txt</a>.</p>"
            + $"<pre class=\"license-text\">{Preformatted(license)}</pre>";
    }

    static string LibraryInformation(LibraryMetadata? metadata, SourceIdentity identity)
    {
        string rows = metadata == null ? "" : $"<tr><td>Library</td><td>{E(metadata.Title)}</td></tr><tr><td>Company</td><td>{E(metadata.Company)}</td></tr>"
            + $"<tr><td>Library version</td><td><code>{E(metadata.Version)}</code></td></tr><tr><td>Namespace</td><td><code>{E(metadata.Namespace)}</code></td></tr>"
            + $"<tr><td>Published framework version</td><td><code>{E(metadata.FrameworkVersion)}</code> (revision omitted)</td></tr>"
            + string.Join("", metadata.Contracts.Select(c => $"<tr><td>{E(c.Title)} contract</td><td><code>{E(c.Version)}</code></td></tr>"));
        rows += $"<tr><td>Source commit</td><td><code>{E(identity.Commit ?? "No project Git identity available")}</code></td></tr>"
            + $"<tr><td>Working tree</td><td>{(identity.WorkingTreeChanged is true ? "Contains local changes; input hashes identify the generated snapshot." : identity.WorkingTreeChanged is false ? "Clean" : "Not identified")}</td></tr>";
        return "<h2>Library and documentation version</h2>" + Table("<th scope=\"col\">Item</th><th scope=\"col\">Value</th>", rows)
            + (metadata == null ? "<p>Library identity has not been bound to a PLC project in this configuration.</p>" : "<p>The documentation describes the saved sources of this library version. Contract versions have independent compatibility meanings.</p>")
            + "<p>Object pages refer to this snapshot; XML format versions are not semantic object versions.</p>"
            + "<p><a href=\"help-build.json\">Documentation source manifest</a> records the source identity and SHA-256 hashes of the generation inputs.</p>";
    }

    public static string Overview(List<Api> apis, ProjectConfiguration config)
    {
        var html = new StringBuilder($"<p class=\"page-kind\">Library overview</p><h1>{E(config.Product)}</h1><div class=\"lead\">{Paragraphs(config.Overview.Introduction)}</div>");
        if (config.Guide is { } guide)
            html.Append($"<h2>Start with the guide</h2><p>{E(guide.Introduction ?? "Read the guide for usage and extension guidance.")}</p><p><a class=\"area-action\" href=\"guide.html\">{E(guide.Title)} →</a></p>");
        html.Append($"<div class=\"reference-summary\"><span><strong>{config.Groups.Count}</strong> areas</span><span><strong>{apis.Count(a => a.Owner == null)}</strong> documented elements</span><a href=\"catalog.html\">Browse the API catalog →</a></div><h2>Explore by area</h2><div class=\"area-grid\">");
        foreach (var (group, i) in config.Groups.Select((g, i) => (g, i)))
            html.Append($"<section class=\"area-card\"><p class=\"page-kind\">{group.Types.Count} {(group.Types.Count == 1 ? "element" : "elements")}</p><h3>{GroupLink(i, group.Title)}</h3><p>{E(group.Description)}</p><a class=\"area-action\" href=\"catalog.html?group={i}\">Browse area →</a></section>");
        html.Append("</div>");
        html.Append("<h2>Explore by element type</h2><p>Use a second route into the same reference. Element types and functional areas can be combined in the catalog.</p><div class=\"element-grid\">");
        foreach (var category in apis.Where(a => a.Owner == null).GroupBy(ElementPresentation.Category).OrderBy(g => ElementPresentation.CategoryOrder(g.Key)))
        {
            string label = ElementPresentation.CategoryLabel(category.Key);
            html.Append($"<a class=\"element-card\" href=\"catalog.html?category={category.Key}\">{ElementPresentation.CategoryIcon(category.Key)}<span><strong>{E(label)}</strong><span>{E(ElementPresentation.CategoryDescription(category.Key))}</span><small>{category.Count()} {(category.Count() == 1 ? "element" : "elements")} in this reference</small></span></a>");
        }
        html.Append("</div>");
        foreach (var section in config.Overview.Sections) html.Append($"<h2>{E(section.Heading)}</h2>{Paragraphs(section.Text)}");
        return html.ToString();
    }

    public static string Catalog(List<Api> apis, ProjectConfiguration config)
    {
        var html = new StringBuilder("<p class=\"page-kind\">Reference index</p><h1>API catalog</h1><p class=\"lead\">Find a library element by name, purpose, area or kind. Select an element to inspect its declaration and members.</p><section class=\"catalog-controls\" hidden aria-label=\"Catalog filters\"><label>Filter elements<input id=\"catalog-query\" type=\"search\" placeholder=\"Name or description…\"></label><label>Area<select id=\"catalog-group\"><option value=\"\">All areas</option>");
        foreach (var (group, i) in config.Groups.Select((g, i) => (g, i))) html.Append($"<option value=\"{i}\">{E(group.Title)}</option>");
        html.Append("</select></label><label>Category<select id=\"catalog-category\"><option value=\"\">All categories</option>");
        foreach (var category in apis.Where(a => a.Owner == null).Select(ElementPresentation.Category).Distinct().OrderBy(ElementPresentation.CategoryOrder))
            html.Append($"<option value=\"{category}\">{E(ElementPresentation.CategoryLabel(category))}</option>");
        html.Append("</select></label><label>Element<select id=\"catalog-kind\"><option value=\"\">All elements</option>");
        foreach (var kind in apis.Where(a => a.Owner == null).Select(Kind).Distinct().Order()) html.Append($"<option>{E(kind)}</option>");
        html.Append("</select></label></section><p id=\"catalog-status\" role=\"status\" aria-live=\"polite\"></p>");
        var rows = new StringBuilder();
        foreach (var api in apis.Where(a => a.Owner == null).OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase))
        {
            int group = config.Groups.FindIndex(g => g.Types.Contains(api.Name));
            rows.Append($"<tr data-entry data-group=\"{group}\" data-kind=\"{E(Kind(api))}\" data-category=\"{ElementPresentation.Category(api)}\"><td><span class=\"type-name\">{ElementPresentation.Icon(Kind(api))}{Link(api)}</span><small>{E(Kind(api))}</small></td><td>{E(api.Docs.Summary.Length == 0 ? "No purpose description available." : api.Docs.Summary)}</td><td>{E(config.Groups[group].Title)}</td></tr>");
        }
        html.Append(Table("<th scope=\"col\">Element</th><th scope=\"col\">Purpose</th><th scope=\"col\">Area</th>", rows.ToString()));
        html.Append("<div class=\"catalog-pagination\" hidden><button id=\"catalog-previous\" type=\"button\">Previous</button><span id=\"catalog-page\"></span><button id=\"catalog-next\" type=\"button\">Next</button></div>");
        return html.ToString();
    }

    static string Relationships(Api item, List<Api> apis)
    {
        List<Api> chain = [item];
        while (chain[0].Base is { } parent) chain.Insert(0, Type(parent, apis));
        var boxes = new StringBuilder(); var edges = new StringBuilder();
        int slot = 0, previousY = 0;
        void Box(Api node, int x, int y)
        {
            string label = node.Name.Length <= 29 ? E(node.Name) : $"<tspan x=\"{x + 14}\">{E(node.Name[..26])}</tspan><tspan x=\"{x + 14}\" dy=\"13\">{E(node.Name[26..])}</tspan>";
            boxes.Append($"<a href=\"{Href(node)}\"><g class=\"class-node{(node == item ? " current" : "")}\"><rect x=\"{x}\" y=\"{y}\" width=\"260\" height=\"62\" rx=\"6\"/><text x=\"{x + 14}\" y=\"{y + 23}\" class=\"class-kind\">{E(Kind(node))}</text><text x=\"{x + 14}\" y=\"{y + 45}\">{label}</text></g></a>");
        }
        foreach (var node in chain)
        {
            int y = 20 + slot * 105;
            Box(node, 20, y);
            if (slot > 0) edges.Append($"<path class=\"extends-edge\" d=\"M150 {y} V{previousY + 62}\" marker-end=\"url(#parent-arrow)\"/>");
            for (int i = 0; i < node.Interfaces.Count; i++)
            {
                int interfaceY = y + i * 105;
                Box(Type(node.Interfaces[i], apis), 420, interfaceY);
                edges.Append($"<path class=\"implements-edge\" d=\"M280 {y + 31} H340 V{interfaceY + 31} H420\" marker-end=\"url(#parent-arrow)\"/><text class=\"edge-label\" x=\"350\" y=\"{interfaceY + 21}\">implements</text>");
            }
            previousY = y; slot += Math.Max(1, node.Interfaces.Count);
        }
        return $"<figure class=\"class-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 700 {slot * 105}\" role=\"img\" aria-label=\"Class relationships for {E(item.Name)}\"><title>Inheritance and implemented interfaces for {E(item.Name)}</title><defs><marker id=\"parent-arrow\" viewBox=\"0 0 12 12\" refX=\"11\" refY=\"6\" markerWidth=\"12\" markerHeight=\"12\" orient=\"auto\"><path d=\"M1 1 L11 6 L1 11 Z\"/></marker></defs>{edges}{boxes}</svg><figcaption>Solid line: extends. Dashed line: implements. Select a type to open its reference.</figcaption></figure>";
    }

    static List<Field> Fields(Api item, List<Api> apis)
    {
        List<Field> result = [.. item.Fields];
        if (item.Owner == null && item.Base != null) result.AddRange(Fields(Type(item.Base, apis), apis).Where(f => !result.Any(own => own.Name == f.Name)));
        return result;
    }

    public static string Page(Api item, List<Api> apis, ProjectConfiguration config)
    {
        var owner = item.Owner == null ? item : Type(item.Owner, apis);
        int group = config.Groups.FindIndex(g => g.Types.Contains(owner.Name));
        var html = new StringBuilder($"<nav class=\"breadcrumbs\" aria-label=\"Breadcrumb\"><a href=\"catalog.html\">API catalog</a><span>/</span>{GroupLink(group, config.Groups[group].Title)}");
        if (item.Owner != null) html.Append($"<span>/</span>{Link(owner)}");
        html.Append($"</nav><p class=\"page-kind element-label\">{ElementPresentation.Icon(Kind(item))}{E(Kind(item))} · {E(item.Access.ToLowerInvariant())}</p><h1>{E(item.Name)}</h1><div class=\"lead\">{Paragraphs(item.Docs.Summary.Length == 0 ? "No local purpose description was found in the saved declaration." : item.Docs.Summary)}</div>");
        html.Append($"<div class=\"signature\"><code>{E(item.Signature)}</code></div>");
        if (item.AliasType != null) html.Append("<h2>Aliased type</h2><p><code>" + TypeName(item.AliasType, apis) + "</code></p>");
        if (item.UnderlyingType != null) html.Append("<p>Underlying type: <code>" + TypeName(item.UnderlyingType, apis) + "</code>.</p>");
        if (item.TypeDefault != null) html.Append("<p>Initial value: <code>" + TypeName(item.TypeDefault, apis) + "</code>.</p>");
        if (item.Kind == "GVL" && item.Signature == "VAR_GLOBAL") html.Append("<p class=\"configuration-note\">Library-owned global storage and bindings. Initializers below are declared startup values, not live runtime values. Observe each field’s ownership and write permissions.</p>");
        if (item.RequiredDependency) html.Append("<p class=\"configuration-note\">Included because an exported declaration requires this type. Its source visibility is internal; this does not make it a general extension point.</p>");
        if (item.Accessors.Count > 0) html.Append("<p>Available accessors: " + E(string.Join(", ", item.Accessors)) + ".</p>");
        if (item.Kind == "GVL" && item.Signature != "VAR_GLOBAL") html.Append(item.IsParameterList
            ? "<p class=\"configuration-note\">These are consumer-overridable compile-time library parameters. Values below are the library defaults, not the effective settings of a consuming application. They are not runtime commands.</p>"
            : "<p class=\"configuration-note\">These are fixed library constants. Their declared values are not consumer-overridable library parameters. Expressions are shown as declared, without evaluation.</p>");
        if (item.Owner == null && (Kind(item) == "Function block" || item.Kind == "Itf")) html.Append("<h2>Class relationships</h2>" + Relationships(item, apis));
        foreach (var direction in Fields(item, apis).GroupBy(f => f.Direction))
        {
            if (direction.Key == "VAR_GLOBAL CONSTANT")
            {
                html.Append(item.IsParameterList ? "<h2>Parameters and default values</h2>" : "<h2>Constants and declared values</h2>");
                var constants = new StringBuilder();
                foreach (var field in direction)
                {
                    string qualified = item.Name + "." + field.Name;
                    string reference = @"\b" + System.Text.RegularExpressions.Regex.Escape(qualified) + @"\b";
                    var users = apis.Where(a => a != item && a.Fields.Select(f => f.Type + " " + f.Default).Append(a.ReturnType ?? "")
                        .Any(text => System.Text.RegularExpressions.Regex.IsMatch(text, reference))).ToList();
                    string usage = users.Count == 0 ? "" : "<p><small>Referenced by declarations in this export: " + string.Join(", ", users.Select(a => Link(a, a.Owner == null ? a.Name : a.Owner + "." + a.Name))) + "</small></p>";
                    constants.Append($"<tr id=\"field-{E(field.Name)}\"><td><code>{E(field.Name)}</code></td><td><code>{TypeName(field.Type, apis)}</code></td><td><code>{TypeName(field.Default!, apis)}</code></td><td>{Paragraphs(item.Docs.Parameters.GetValueOrDefault(field.Name, field.Comment))}{usage}</td></tr>");
                }
                html.Append(Table($"<th scope=\"col\">Name</th><th scope=\"col\">Type</th><th scope=\"col\">{(item.IsParameterList ? "Library default" : "Declared value")}</th><th scope=\"col\">Description</th>", constants.ToString(), "api-table constant-table"));
                continue;
            }
            string heading = direction.Key switch { "STRUCT" or "UNION" => "Fields", "ENUM" => "Values", "VAR_GLOBAL" => "Global variables", "VAR_INPUT" => "Inputs", "VAR_OUTPUT" => "Outputs", "VAR_IN_OUT" => "In-out parameters", "VAR_IN_OUT CONSTANT" => "Read-only references", _ => direction.Key };
            html.Append($"<h2>{E(heading)}</h2>"); var rows = new StringBuilder();
            foreach (var field in direction)
            {
                var declared = apis.First(a => a.Fields.Any(f => ReferenceEquals(f, field)));
                string description = declared.Docs.Parameters.GetValueOrDefault(field.Name, field.Comment);
                rows.Append($"<tr id=\"field-{E(field.Name)}\"><td><code>{E(field.Name)}</code>{(declared != item ? "<small>Inherited from " + Link(declared) + "</small>" : "")}</td><td><code>{TypeName(field.Type, apis)}</code>{(field.Default != null ? "<small>Default: <code>" + TypeName(field.Default, apis) + "</code></small>" : "")}</td><td>{Paragraphs(description)}</td></tr>");
            }
            html.Append(Table("<th scope=\"col\">Name</th><th scope=\"col\">Type / default</th><th scope=\"col\">Description</th>", rows.ToString()));
        }
        if (item.ReturnType != null)
            html.Append($"<h2>{(item.Kind == "Property" ? "Property value" : "Return value")}</h2><div class=\"value-description\"><code>{TypeName(item.ReturnType, apis)}</code>{Paragraphs(item.Docs.Returns.Length > 0 ? item.Docs.Returns : item.ReturnComment)}</div>");
        if (item.Owner == null)
        {
            foreach (var members in HelpRenderer.Effective(item, apis).GroupBy(a => a.Owner == item.Name ? (a.Kind == "Property" ? "Properties" : "Methods") : (a.Kind == "Property" ? "Inherited properties" : "Inherited methods")))
            {
                html.Append($"<h2>{E(members.Key)}</h2>"); var rows = new StringBuilder();
                foreach (var member in members.OrderBy(a => a.Name))
                    rows.Append($"<tr><td>{Link(member)}<small>{E(member.Access.ToLowerInvariant())}{(member.ReturnType != null ? " · " + E(member.ReturnType) : "")}</small></td><td>{Paragraphs(member.Docs.Summary)}</td><td>{Link(Type(member.Owner!, apis))}</td></tr>");
                html.Append(Table("<th scope=\"col\">Member</th><th scope=\"col\">Purpose</th><th scope=\"col\">Declared by</th>", rows.ToString()));
            }
        }
        if (item.Docs.Remarks.Length > 0) html.Append("<h2>Remarks</h2>" + Paragraphs(item.Docs.Remarks));
        string declaration = item.Kind == "GVL" ? "" : item.Signature;
        if (item.Kind == "DUT") declaration = item.Declaration;
        foreach (var block in (item.Kind == "DUT" ? Enumerable.Empty<IGrouping<string, Field>>() : item.Fields.GroupBy(f => f.Direction)))
            declaration += "\n" + block.Key + "\n" + string.Join("\n", block.Select(f => "    " + f.Name + " : " + f.Type + (f.Default == null ? "" : " := " + f.Default) + ";")) + "\n" + (block.Key == "STRUCT" ? "END_STRUCT\nEND_TYPE" : "END_VAR");
        html.Append($"<h2>Declaration and source</h2><details class=\"declaration-details\"><summary>Structured Text declaration</summary><pre><code>{Preformatted(declaration)}</code></pre><p class=\"source-path\">Source: <code>{E(item.Source)}</code></p></details>");
        return html.ToString();
    }
}
