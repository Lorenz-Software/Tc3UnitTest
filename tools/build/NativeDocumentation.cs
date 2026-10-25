using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;

namespace Tc3UnitTest.Build
{
    public sealed class NativeDocumentationProjection
    {
        public string Content;
        public string CodeHash;
    }

    // A comment-only projection for disposable library sources, not an ST rewriter.
    public static class NativeDocumentation
    {
        private static XmlDocument Load(string text)
        {
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
            var doc = new XmlDocument { PreserveWhitespace = true, XmlResolver = null };
            using (var reader = XmlReader.Create(new StringReader(text), settings)) doc.Load(reader);
            return doc;
        }

        private static int QuotedEnd(string text, int start)
        {
            char quote = text[start];
            for (int i = start + 1; i < text.Length; i++)
            {
                if (text[i] == '$') { i++; continue; }
                if (text[i] != quote) continue;
                if (i + 1 < text.Length && text[i + 1] == quote) { i++; continue; }
                return i + 1;
            }
            throw new FormatException("Unclosed ST string.");
        }

        private static int BlockEnd(string text, int start)
        {
            int depth = 1;
            for (int i = start + 2; i < text.Length - 1; i++)
            {
                if (text[i] == '(' && text[i + 1] == '*') { depth++; i++; }
                else if (text[i] == '*' && text[i + 1] == ')')
                {
                    if (--depth == 0) return i + 2;
                    i++;
                }
            }
            throw new FormatException("Unclosed ST block comment.");
        }

        private static string Render(XmlNode node)
        {
            if (node is XmlText || node is XmlCDataSection || node is XmlWhitespace ||
                node is XmlSignificantWhitespace) return node.Value;
            var element = node as XmlElement;
            if (element == null) throw new FormatException("Unsupported documentation node.");
            if (element.NamespaceURI.Length != 0) throw new FormatException("Namespaced documentation is unsupported.");
            if (element.Name != "summary" && element.Name != "description" && element.Name != "param" &&
                element.Name != "returns" && element.Name != "c" && element.Name != "code")
                throw new FormatException("Unsupported native documentation markup: " + element.Name);
            foreach (XmlAttribute attribute in element.Attributes)
                if (element.Name != "param" || attribute.Name != "name")
                    throw new FormatException("Unsupported documentation attribute: " + attribute.Name);
            var result = new StringBuilder();
            foreach (XmlNode child in node.ChildNodes) result.Append(Render(child));
            string value = result.ToString();
            if (element.Name == "param")
            {
                string name = element.GetAttribute("name");
                if (String.IsNullOrWhiteSpace(name)) throw new FormatException("Unnamed parameter documentation.");
                return name + ": " + value.Trim();
            }
            if (element.Name == "returns") return "Returns: " + value.Trim();
            return value;
        }

        private static string PlainHeader(string body)
        {
            var doc = Load("<doc>" + body + "</doc>");
            var parts = new List<string>();
            foreach (XmlNode node in doc.DocumentElement.ChildNodes)
            {
                if (node is XmlWhitespace || node is XmlSignificantWhitespace) continue;
                if (!(node is XmlElement)) throw new FormatException("Expected structured documentation sections.");
                parts.Add(Render(node).Trim());
            }
            string text = String.Join("\r\n\r\n", parts.ToArray());
            // Never introduce an ST comment delimiter through XML entity decoding.
            if (text.Contains("(*") || text.Contains("*)"))
                throw new FormatException("Documentation contains native block-comment delimiters.");
            return "(*\r\n" + text + "\r\n*)";
        }

        public static string Declaration(string text)
        {
            var result = new StringBuilder();
            for (int i = 0; i < text.Length;)
            {
                int end;
                if (text[i] == '\'' || text[i] == '"')
                {
                    end = QuotedEnd(text, i);
                    result.Append(text, i, end - i); i = end;
                }
                else if (i + 1 < text.Length && text[i] == '/' && text[i + 1] == '/')
                {
                    end = text.IndexOf('\n', i);
                    if (end < 0) end = text.Length;
                    string comment = text.Substring(i, end - i);
                    if (comment.StartsWith("//!"))
                    {
                        string body = comment.Substring(3);
                        if (body.TrimStart().StartsWith("<"))
                            throw new FormatException("Use the reviewed block header for structured documentation.");
                        result.Append("//").Append(body);
                    }
                    else if (Regex.IsMatch(comment, @"^///?\s*SA\d{4}:"))
                    {
                        // Retain rationale in canonical sources; native GVL comment association can
                        // select even ordinary leading comments instead of the actual field meaning.
                    }
                    else result.Append(comment);
                    i = end;
                }
                else if (i + 1 < text.Length && text[i] == '(' && text[i + 1] == '*')
                {
                    end = BlockEnd(text, i);
                    if (i + 2 < text.Length && text[i + 2] == '!')
                        result.Append(PlainHeader(text.Substring(i + 3, end - i - 5)));
                    else result.Append(text, i, end - i);
                    i = end;
                }
                else result.Append(text[i++]);
            }
            string projected = result.ToString();
            if (Tokens(text) != Tokens(projected)) throw new InvalidOperationException("Documentation projection changed ST tokens.");
            return projected;
        }

        // Token boundaries and quoted contents matter: A B must not compare equal to AB.
        private static string Tokens(string text)
        {
            var result = new StringBuilder();
            for (int i = 0; i < text.Length;)
            {
                if (Char.IsWhiteSpace(text[i])) { i++; continue; }
                if (i + 1 < text.Length && text[i] == '/' && text[i + 1] == '/')
                {
                    int end = text.IndexOf('\n', i); i = end < 0 ? text.Length : end; continue;
                }
                if (i + 1 < text.Length && text[i] == '(' && text[i + 1] == '*')
                { i = BlockEnd(text, i); continue; }
                int start = i;
                if (text[i] == '\'' || text[i] == '"') i = QuotedEnd(text, i);
                else if (Char.IsLetterOrDigit(text[i]) || text[i] == '_')
                    while (i < text.Length && (Char.IsLetterOrDigit(text[i]) || text[i] == '_')) i++;
                else if (i + 1 < text.Length &&
                    (text.Substring(i, 2) == ":=" || text.Substring(i, 2) == "=>" ||
                     text.Substring(i, 2) == "<=" || text.Substring(i, 2) == ">=" ||
                     text.Substring(i, 2) == "<>" || text.Substring(i, 2) == "**" ||
                     text.Substring(i, 2) == "..")) i += 2;
                else i++;
                result.Append(i - start).Append(':').Append(text, start, i - start).Append(';');
            }
            return result.ToString();
        }

        public static string CodeHash(string content)
        {
            var doc = Load(content);
            foreach (XmlNode node in doc.SelectNodes("//Declaration"))
                node.InnerText = Tokens(node.InnerText);
            // Ignore XML indentation; retain all non-declaration nodes, attributes and implementation.
            var canonical = new XmlDocument { PreserveWhitespace = false, XmlResolver = null };
            canonical.LoadXml(doc.DocumentElement.OuterXml);
            using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(canonical.DocumentElement.OuterXml))).Replace("-", "");
        }

        public static NativeDocumentationProjection Project(string content)
        {
            var doc = Load(content);
            if (doc.DocumentElement.Name != "TcPlcObject") throw new FormatException("Expected TwinCAT PLC source XML.");
            string before = CodeHash(content);
            foreach (XmlNode node in doc.SelectNodes("//Declaration"))
            {
                string text = Declaration(node.InnerText);
                while (node.HasChildNodes) node.RemoveChild(node.FirstChild);
                node.AppendChild(doc.CreateCDataSection(text));
            }
            var settings = new XmlWriterSettings { Encoding = new UTF8Encoding(false), Indent = false,
                NewLineChars = "\r\n", NewLineHandling = NewLineHandling.Replace };
            string projected;
            using (var stream = new MemoryStream())
            {
                using (var writer = XmlWriter.Create(stream, settings)) doc.Save(writer);
                projected = Encoding.UTF8.GetString(stream.ToArray());
            }
            if (before != CodeHash(projected)) throw new InvalidOperationException("Native documentation changed non-comment source XML.");
            return new NativeDocumentationProjection { Content = projected, CodeHash = before };
        }
    }
}
