using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

sealed record HelpAttribution(string Author, string ContactEmail, string Copyright, string LicenseName, string LicenseFile, string? Website = null, string? LogoFile = null, string? HeaderLogoFile = null);
sealed record HelpSection(string Heading, string Text);
sealed record HelpOverview(string Title, string Introduction, List<HelpSection> Sections);
sealed record HelpGroup(string Title, string Description, List<string> Types, string? SourcePrefix = null);
sealed record HelpExclusion(string Name, string Reason);
sealed record HelpSelection(string ProjectFile, List<HelpExclusion> Exclusions);
sealed record HelpChapter(string File, List<string> ApiTypes);
sealed record HelpGuide(string Title, string SourceRoot, List<HelpChapter> Chapters, string? Introduction = null);
sealed record ContractVersionSource(string Title, string File, string ConstantsFile, string Constant);
sealed record LibraryMetadataSource(string ProjectFile, string GeneratedVersionFile, string GeneratedVersionSymbol, List<ContractVersionSource> Contracts);
sealed record ProjectConfiguration(string SourceRoot, List<string> IncludeTypes,
    string Product, string BrandMark, string Subtitle, string Edition,
    string PackageFile, string Stylesheet, HelpOverview Overview, List<HelpGroup> Groups, HelpAttribution Attribution,
    HelpGuide? Guide = null, LibraryMetadataSource? Library = null, string? LibraryNamespace = null, string? Publisher = null, HelpSelection? Selection = null)
{
    public static ProjectConfiguration Load(string path)
    {
        var config = JsonSerializer.Deserialize<ProjectConfiguration>(File.ReadAllText(path), new JsonSerializerOptions {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase, RespectRequiredConstructorParameters = true,
            UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
        }) ?? throw new FormatException("Missing project configuration.");
        if (config.LibraryNamespace != null && !Regex.IsMatch(config.LibraryNamespace, @"^[A-Za-z_][A-Za-z0-9_.]*$")) throw new FormatException("Invalid library namespace.");
        if (config.Library == null && (config.LibraryNamespace == null || string.IsNullOrWhiteSpace(config.Publisher)))
            throw new FormatException("A project metadata source or explicit namespace and publisher are required.");
        if ((config.IncludeTypes.Count == 0 && config.Selection == null) || config.IncludeTypes.Distinct().Count() != config.IncludeTypes.Count)
            throw new FormatException("Included types must be non-empty and unique.");
        if (config.Selection != null && (config.IncludeTypes.Count != 0 || config.Groups.Any(g => g.Types.Count != 0 || string.IsNullOrWhiteSpace(g.SourcePrefix))
            || config.Selection.Exclusions.Any(e => string.IsNullOrWhiteSpace(e.Reason))
            || config.Selection.Exclusions.Select(e => e.Name).Distinct().Count() != config.Selection.Exclusions.Count))
            throw new FormatException("Automatic selection requires area prefixes, empty explicit selections and unique explained exclusions.");
        var grouped = config.Groups.SelectMany(g => g.Types).ToList();
        if (grouped.Count != config.IncludeTypes.Count || grouped.Distinct().Count() != grouped.Count || grouped.Except(config.IncludeTypes).Any())
            throw new FormatException("Each selected type must belong to exactly one project group.");
        if (Path.GetFileName(config.PackageFile) != config.PackageFile || !config.PackageFile.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            throw new FormatException("Package file must be a ZIP file name.");
        if (string.IsNullOrWhiteSpace(config.Attribution.Author) || string.IsNullOrWhiteSpace(config.Attribution.Copyright)
            || string.IsNullOrWhiteSpace(config.Attribution.LicenseName)
            || !System.Net.Mail.MailAddress.TryCreate(config.Attribution.ContactEmail, out var contact)
            || contact.Address != config.Attribution.ContactEmail)
            throw new FormatException("Author, copyright, license and a valid contact email are required.");
        if (config.Attribution.Website is { } website && (!Uri.TryCreate(website, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("https" or "http"))) throw new FormatException("Author website must be an absolute HTTP(S) URL.");
        foreach (var logo in new[] { config.Attribution.LogoFile, config.Attribution.HeaderLogoFile }.OfType<string>())
            if (!new[] { ".png", ".jpg", ".jpeg", ".webp", ".svg" }.Contains(Path.GetExtension(logo).ToLowerInvariant()))
                throw new FormatException("Author logos must be PNG, JPEG, WebP or SVG files.");
        if (config.Guide is { } guide)
        {
            if (string.IsNullOrWhiteSpace(guide.Title) || guide.Chapters.Count == 0
                || guide.Chapters.Select(c => c.File).Distinct(StringComparer.OrdinalIgnoreCase).Count() != guide.Chapters.Count)
                throw new FormatException("A guide needs a title and unique chapters.");
            foreach (var chapter in guide.Chapters)
                if (!Regex.IsMatch(chapter.File, @"^[a-zA-Z0-9][a-zA-Z0-9_-]*\.md$")
                    || new[] { "index", "catalog", "about", "guide" }.Contains(Path.GetFileNameWithoutExtension(chapter.File), StringComparer.OrdinalIgnoreCase)
                    || chapter.ApiTypes.Any(string.IsNullOrWhiteSpace) || chapter.ApiTypes.Distinct().Count() != chapter.ApiTypes.Count)
                    throw new FormatException("Invalid guide chapter or API mapping: " + chapter.File);
        }
        return config;
    }

    public static string ConfinedPath(string root, string relative)
    {
        string prefix = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar;
        string result = Path.GetFullPath(Path.Combine(prefix, relative));
        if (Path.IsPathRooted(relative) || !result.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new FormatException("Project path must remain below its owning directory: " + relative);
        return result;
    }
}
