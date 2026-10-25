using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinCatDocumentation;

static class Program
{
    static int Main(string[] args)
    {
        try
        {
            if (args is ["--self-test"]) ParserChecks.SelfTest();
            else if (args is ["--audit-comments", var auditRepo, var ledger, var auditOutput, var policy])
                SourceCommentAudit.Run(Path.GetFullPath(auditRepo), Path.GetFullPath(ledger), Path.GetFullPath(auditOutput), Path.GetFullPath(policy));
            else if (args is ["--inventory", var repository, var project, var inventoryOutput])
                ProjectInventory.Run(Path.GetFullPath(repository), Path.GetFullPath(project), Path.GetFullPath(inventoryOutput));
            else if (args is ["--inventory", var scopedRepository, var scopedProject, var scopedOutput, var scope])
                ProjectInventory.Run(Path.GetFullPath(scopedRepository), Path.GetFullPath(scopedProject), Path.GetFullPath(scopedOutput), Path.GetFullPath(scope));
            else if (args.Length == 4) DocumentationBuild.Run(Path.GetFullPath(args[0]), Path.GetFullPath(args[1]), Path.GetFullPath(args[2]), Path.GetFullPath(args[3]));
            else throw new ArgumentException("Usage: TwinCatDocumentation <repository> <output> <project-config> <template> | --inventory <repository> <plcproj> <output> [scope] | --audit-comments <repository> <inventory> <output> <policy> | --self-test");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.ToString()); return 1; }
    }
}
