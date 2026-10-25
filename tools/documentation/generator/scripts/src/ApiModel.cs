using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

record Token(string Text, string Kind, int Start, int End, int Line);
record Field(string Name, string Type, string? Default, string Comment, string Direction);
record Docs(string Summary, string Remarks, Dictionary<string, string> Parameters, string Returns);
sealed class Api
{
    public required string Name { get; init; }
    public required string Uid { get; init; }
    public required string Kind { get; init; }
    public required string Source { get; init; }
    public required string Access { get; init; }
    public required string Signature { get; init; }
    public required Docs Docs { get; init; }
    public string? Owner { get; init; }
    public string? Base { get; init; }
    public List<string> Interfaces { get; init; } = [];
    public string? ReturnType { get; init; }
    public string ReturnComment { get; init; } = "";
    public List<Field> Fields { get; init; } = [];
    public string Declaration { get; init; } = "";
    public string? DataKind { get; init; }
    public string? AliasType { get; init; }
    public string? UnderlyingType { get; init; }
    public string? TypeDefault { get; init; }
    public bool RequiredDependency { get; set; }
    public List<string> Accessors { get; init; } = [];
    public bool IsParameterList { get; init; }
}
