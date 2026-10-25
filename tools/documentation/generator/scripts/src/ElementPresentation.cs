namespace TwinCatDocumentation;

// Reusable visual vocabulary. Classification does not add parser coverage.
static class ElementPresentation
{
    public static string Label(Api api) => api.Kind switch {
        "POU" when api.Signature.StartsWith("FUNCTION_BLOCK ", StringComparison.OrdinalIgnoreCase) => "Function block",
        "POU" when api.Signature.StartsWith("FUNCTION ", StringComparison.OrdinalIgnoreCase) => "Function",
        "POU" when api.Signature.StartsWith("PROGRAM ", StringComparison.OrdinalIgnoreCase) => "Program",
        "Itf" => "Interface", "DUT" => api.DataKind ?? "Structure", "GVL" when api.IsParameterList => "Parameter list", "GVL" when api.Signature == "VAR_GLOBAL" => "Global variables", "GVL" => "Constant list", _ => api.Kind
    };

    public static string Category(Api api) => api.Kind switch {
        "POU" when Label(api) is "Function block" or "Function" => "blocks",
        "DUT" => "data", "Itf" => "interfaces", "GVL" => "configuration", _ => "other"
    };

    public static string CategoryLabel(string category) => category switch {
        "blocks" => "Blocks", "data" => "Data types", "interfaces" => "Interfaces", "configuration" => "Parameters and constants", _ => "Other elements"
    };

    public static int CategoryOrder(string category) => category switch {
        "data" => 0, "interfaces" => 1, "blocks" => 2, "configuration" => 3, _ => 4
    };

    public static string CategoryDescription(string category) => category switch {
        "blocks" => "Function blocks and functions: inspect their callable interfaces and behavior.",
        "data" => "Inspect the shape, fields and values of library data types.",
        "interfaces" => "Explore the methods and properties exposed by library interfaces.",
        "configuration" => "Inspect consumer-overridable library parameters and fixed constants.",
        _ => "Explore additional PLC element kinds documented by this library."
    };

    public static string CategoryIcon(string category) => Icon(category switch {
        "blocks" => "Function block", "data" => "Structure", "interfaces" => "Interface", "configuration" => "Parameter list", _ => "Other"
    });

    public static string Icon(string kind)
    {
        var (symbol, drawing) = kind switch {
            "Function block" => ("fb", "<rect x=\"5\" y=\"3\" width=\"14\" height=\"18\" rx=\"2\"/><path d=\"M5 8h14M1 11h4m-4 6h4m14-6h4m-4 6h4\"/>"),
            "Function" => ("function", "<path d=\"M16 4c-4-2-6 0-6 4l-1 8c0 4-2 5-5 4M5 10h11\"/>"),
            "Structure" or "Union" or "Enumeration" or "Alias" => ("data", "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"2\"/><path d=\"M3 9h18M3 15h18M9 3v18\"/>"),
            "Interface" => ("interface", "<circle cx=\"14\" cy=\"12\" r=\"7\"/><path d=\"M1 12h6\"/>"),
            "Method" => ("method", "<path d=\"M7 5 2 12l5 7m10-14 5 7-5 7M14 5l-4 14\"/>"),
            "Property" => ("property", "<path d=\"M4 6h16M4 18h16M8 3v6m8 6v6\"/><circle cx=\"8\" cy=\"6\" r=\"2\"/><circle cx=\"16\" cy=\"18\" r=\"2\"/>"),
            "Parameter list" or "Constant list" or "Global variables" => ("configuration", "<path d=\"M3 6h18M3 12h18M3 18h18M8 3v6m8 0v6m-8 0v6\"/>"),
            _ => ("other", "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"3\"/><path d=\"M8 12h8m-4-4v8\"/>")
        };
        return $"<svg class=\"element-symbol symbol--{symbol}\" viewBox=\"0 0 24 24\" aria-hidden=\"true\" focusable=\"false\" width=\"24\" height=\"24\">{drawing}</svg>";
    }
}
