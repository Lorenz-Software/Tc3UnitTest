using System.Diagnostics;
using System.Security.Cryptography;

namespace TwinCatDocumentation;

sealed record SourceIdentity(string? Commit, bool? WorkingTreeChanged);

sealed class BuildEvidence
{
    readonly Dictionary<string, (string Path, string Hash)> inputs = new(StringComparer.OrdinalIgnoreCase);
    public static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    public void Add(string label, string path)
    {
        if (!inputs.TryAdd(label.Replace('\\', '/'), (path, Hash(path)))) throw new FormatException("Duplicate evidence label: " + label);
    }
    public Dictionary<string, string> Hashes => inputs.OrderBy(p => p.Key, StringComparer.Ordinal).ToDictionary(p => p.Key, p => p.Value.Hash);
    public void Verify()
    {
        foreach (var (label, item) in inputs)
            if (Hash(item.Path) != item.Hash) throw new IOException("Documentation input changed during generation: " + label);
    }

    public static SourceIdentity Git(string repo)
    {
        string? Run(params string[] arguments)
        {
            var start = new ProcessStartInfo("git") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("-C"); start.ArgumentList.Add(repo);
            foreach (var argument in arguments) start.ArgumentList.Add(argument);
            using var process = Process.Start(start) ?? throw new IOException("Cannot start Git.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            process.WaitForExit();
            Task.WaitAll(stdout, stderr);
            return process.ExitCode == 0 ? stdout.Result.Trim() : null;
        }
        var root = Run("rev-parse", "--show-toplevel");
        if (root == null || !Path.GetFullPath(root).Equals(Path.GetFullPath(repo), StringComparison.OrdinalIgnoreCase)) return new(null, null);
        string? commit = Run("rev-parse", "HEAD"), status = Run("status", "--porcelain", "--untracked-files=normal");
        if (commit == null || status == null) throw new IOException("Unable to identify Git source state.");
        return new(commit, status.Length != 0);
    }
}
