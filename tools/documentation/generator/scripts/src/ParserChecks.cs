using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

static class ParserChecks
{
    public static void SelfTest()
    {
        int tests = 0;
        void Check(bool condition, string label) { if (!condition) throw new Exception("FAIL: " + label); tests++; }
        void Reject(Action operation, string label) { try { operation(); } catch (Exception error) when (error is FormatException or System.Xml.XmlException) { tests++; return; } throw new Exception("FAIL: expected rejection: " + label); }
        string source = "//! <summary>Probe</summary>\n//! <remarks><para>First.</para><para>Second.</para></remarks>\nMETHOD PROTECTED Probe : BOOL // success flag\nVAR_IN_OUT CONSTANT\n    /// Shared buffer.\n    {attribute 'TcNoSymbol'}\n    Buffer : ARRAY[*] OF BYTE;\nEND_VAR\nVAR_INPUT\n    Text : STRING(80) := 'a; // b'; // Literal text.\nEND_VAR";
        var parsed = Parser.Parse("Probe", "Method", source, "fixture", "Owner");
        Check(parsed.Fields.Count == 2, "semicolon/comment markers in strings do not split fields");
        Check(parsed.Fields[0].Type == "ARRAY[*] OF BYTE", "open-array type remains exact");
        Check(parsed.Fields[0].Direction == "VAR_IN_OUT CONSTANT", "in-out direction retained");
        Check(parsed.Fields[0].Comment == "Shared buffer.", "preceding native comment survives intervening attribute");
        Check(parsed.Fields[1].Default == "'a; // b'" && parsed.Fields[1].Comment == "Literal text.", "literal initializer and native trailing comment");
        Check(parsed.ReturnComment == "success flag" && parsed.ReturnType == "BOOL", "native return comment retained");
        Check(parsed.Docs.Remarks.Contains("First.") && parsed.Docs.Remarks.Contains("Second."), "remarks and paragraphs retained");
        Check(parsed.Access == "PROTECTED", "protected visibility retained");
        var canonicalSource = "{region 'Documentation'}\n(*!\n<summary>Configure.</summary>\n<description>Longer usage constraints.</description>\n*)\n{endregion}\nMETHOD PUBLIC M : BOOL //! Success result.\nVAR_INPUT\nValue : INT; //! Input meaning.\nEND_VAR";
        var canonical = Parser.Parse("M", "Method", canonicalSource, "fixture", "Owner");
        Check(canonical.Docs.Summary == "Configure." && canonical.Docs.Remarks == "Longer usage constraints.", "TE1030 description is preserved without requiring remarks/para");
        Check(canonical.Fields.Single().Comment == "Input meaning." && canonical.ReturnComment == "Success result.", "TE-marked native input and return comments are retained");
        List<InventoryItem> canonicalInventory = [];
        ProjectInventory.AddDeclaration(canonicalInventory, canonicalSource, "fixture::Owner.M[Method]", null, "fixture", "Example", "Owner.M", "Method", "Project source", "fixture-hash", 1);
        Check(canonicalInventory[0].DocumentationForm == "TE-marked documentation" && canonicalInventory[0].Signature == "METHOD PUBLIC M : BOOL"
            && canonicalInventory.Single(i => i.QualifiedName == "Owner.M.Value").NativeComment == "Input meaning.", "documentation region and block header preserve inventory signature and element association");
        var auditPolicy = new CommentAuditPolicy("Documentation", ["summary", "description", "param", "c", "code"]);
        Check(SourceCommentAudit.CheckHeader(canonicalSource, auditPolicy).Count == 0, "canonical region/block header passes source format independently of extraction");
        var withoutRegion = canonicalSource.Replace("{region 'Documentation'}\n", "").Replace("{endregion}\n", "");
        Check(SourceCommentAudit.CheckHeader(withoutRegion, auditPolicy).Any(f => f.Code == "documentation-region"), "missing region is a source finding despite valid exported descriptions");
        var lineHeader = "{region 'Documentation'}\n//! <summary>Configure.</summary>\n{endregion}\nMETHOD M";
        Check(SourceCommentAudit.CheckHeader(lineHeader, auditPolicy).Any(f => f.Code == "header-block"), "line documentation cannot silently replace the agreed block header");
        Check(SourceCommentAudit.CheckHeader("// {region 'Documentation'}\n" + withoutRegion, auditPolicy).Any(f => f.Code == "documentation-region"), "region text inside a comment does not establish a folding boundary");
        Check(SourceCommentAudit.CheckHeader(canonicalSource.Replace("</summary>", ""), auditPolicy).Any(f => f.Code == "documentation-xml"), "malformed documentation is a source finding");
        Check(SourceCommentAudit.CheckHeader(canonicalSource.Replace("{endregion}\nMETHOD", "{attribute 'hide'}\n{endregion}\nMETHOD"), auditPolicy).Any(f => f.Code == "documentation-region"), "attributes are not hidden inside the documentation region");
        Check(SourceCommentAudit.CheckHeader(canonicalSource.Replace("<description>", "<remarks>").Replace("</description>", "</remarks>"), auditPolicy).Any(f => f.Code == "markup-review"), "legacy tolerant markup remains a source-profile finding");
        var blockComment = Parser.Parse("M", "Method", "METHOD M\nVAR_INPUT\nValue : INT; (*! Block input meaning. *)\nOther : BOOL; // ! means negation here.\nEND_VAR", "fixture", "Owner");
        Check(blockComment.Fields[0].Comment == "Block input meaning." && blockComment.Fields[1].Comment == "! means negation here.", "strip only TE marker punctuation, preserving ordinary comment content");
        Check(Parser.Lex("(* outer (* nested *) end *) METHOD M").Count == 3, "nested block comments");
        Reject(() => Parser.Lex("(* unterminated"), "unterminated comment");
        Reject(() => Parser.Lex("'unterminated"), "unterminated literal");
        var enumeration = Parser.Parse("X", "DUT", "TYPE X : (A := -10, //! Negative value.\nB := 20 //! Positive value.\n) INT := B; END_TYPE", "fixture");
        Check(enumeration.DataKind == "Enumeration" && enumeration.Fields.Count == 2 && enumeration.Fields[0].Default == "-10" && enumeration.Fields[1].Comment == "Positive value.", "enum values, defaults and native descriptions survive");
        Check(enumeration.UnderlyingType == "INT" && enumeration.TypeDefault == "B" && enumeration.Declaration.Contains("INT := B"), "enum underlying type and default retained");
        Check(Parser.Parse("X", "DUT", "TYPE INTERNAL X : UNION A : REAL; B : DWORD; END_UNION END_TYPE", "fixture").Fields.Count == 2, "internal union fields retained");
        Check(Parser.Parse("X", "DUT", "TYPE X : Other; END_TYPE", "fixture").DataKind == "Alias", "alias classification");
        Reject(() => Parser.Parse("X", "DUT", "TYPE X : (A := ) INT; END_TYPE", "fixture"), "malformed enum fails");
        Reject(() => Parser.Parse("M", "Method", "//! <remarks>broken\nMETHOD M", "fixture"), "malformed documentation XML");
        Reject(() => Parser.Parse("M", "Method", "//! <param name=\"X\">other</param>\nMETHOD M\nVAR_INPUT\nX : BOOL; // native\nEND_VAR", "fixture"), "conflicting native and markup descriptions");
        var parent = Parser.Parse("Parent", "POU", "FUNCTION_BLOCK Parent", "fixture");
        var child = Parser.Parse("Child", "POU", "FUNCTION_BLOCK Child EXTENDS Parent", "fixture");
        var method = Parser.Parse("M", "Method", "METHOD PROTECTED M", "fixture", "Parent");
        Check(HelpRenderer.Effective(child, [parent, child, method]).Single().Uid == "Library.Parent.M", "inherited protected member links to actual declaration");
        var cycle = Parser.Parse("Parent", "POU", "FUNCTION_BLOCK Parent EXTENDS Child", "fixture");
        Reject(() => HelpRenderer.Effective(child, [cycle, child]), "inheritance cycle");
        var parameters = Parser.ParseConstants("Limits", "/// Compile-time capacities.\n{attribute 'qualified_only'}\nVAR_GLOBAL CONSTANT\n/// Capacity in bytes.\n{attribute 'TcNoSymbol'}\nSize : UINT := 80;\nText : STRING(10) := 'a; // b'; // Literal default.\nEND_VAR", "fixture", "Example", true);
        Check(parameters.IsParameterList && parameters.Kind == "GVL" && parameters.Fields.Count == 2, "parameter list classification and values");
        Check(parameters.Fields[0].Comment == "Capacity in bytes." && parameters.Fields[1].Default == "'a; // b'", "GVL comments and quoted default remain intact");
        Check(Parser.ParseConstants("X", "VAR_GLOBAL X : UINT := 1; END_VAR", "fixture", "Example", false).Signature == "VAR_GLOBAL", "global storage is distinct from constants");
        Reject(() => Parser.ParseConstants("X", "VAR_GLOBAL CONSTANT X : UINT; END_VAR", "fixture", "Example", false), "missing constant initializer");
        Reject(() => Parser.ParseConstants("X", "VAR_GLOBAL CONSTANT X : UINT := 1 END_VAR", "fixture", "Example", false), "unterminated constant declaration");
        Check(LibraryMetadata.VersionParts("1.2.3.0", 4).SequenceEqual(new[] { 1, 2, 3, 0 }), "four-component library version");
        Reject(() => LibraryMetadata.VersionParts("1.2.65536.0", 4), "version component exceeds generated UINT representation");
        var markup = Parser.Parse("M", "Method", "(*! <summary>Use <c>Value</c>.</summary><description><code>Value := 1;&lt;2</code></description> *) METHOD M", "fixture");
        Check(ApiPresentation.Paragraphs(markup.Docs.Summary).Contains("<code>Value</code>"), "inline documentation code renders semantically");
        Check(ApiPresentation.Paragraphs(markup.Docs.Remarks).Contains("<pre><code>Value := 1;&lt;2</code></pre>"), "documentation code preserves whitespace and escapes markup");
        var left = Parser.Parse("Left", "POU", "FUNCTION_BLOCK Left\nVAR_INPUT Value : INT; END_VAR", "fixture");
        var right = Parser.Parse("Right", "POU", "FUNCTION_BLOCK Right\nVAR_INPUT Value : INT; END_VAR", "fixture");
        var config = new ProjectConfiguration("plc", ["Left", "Right"], "Fixture", "F", "Fixture", "Fixture", "fixture.zip", "style.css",
            new HelpOverview("Fixture", "Fixture", []), [new HelpGroup("Area", "Fixture", ["Left", "Right"])],
            new HelpAttribution("Fixture", "a@example.com", "Fixture", "Fixture", "LICENSE"), LibraryNamespace: "Library", Publisher: "Fixture");
        Check(!ApiPresentation.Page(right, [left, right], config).Contains("Inherited from"), "equal-valued fields on unrelated blocks retain their actual declaring owner");
        Console.WriteLine($"PASS: {tests} focused parser/model checks.");
    }
}
