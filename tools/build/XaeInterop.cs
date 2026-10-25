using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using EnvDTE;
using EnvDTE80;
using TCatSysManagerLib;

namespace Tc3UnitTest.Build
{
    public sealed class XaeSession
    {
        public string Moniker;
        public string SolutionPath;
        public object Dte;
        public string[] Projects;
    }

    public sealed class Diagnostic
    {
        public string Severity;
        public string Description;
        public string File;
        public int Line;
        public string Project;
    }

    public sealed class LibraryReference
    {
        public string Name;
        public string Kind;
        public string Title;
        public string Version;
        public string Company;
    }

    // Typed calls are needed for TwinCAT IUnknown interfaces and DTE's ErrorList.
    public static class XaeInterop
    {
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        public static int ProcessId(object raw)
        {
            uint id;
            GetWindowThreadProcessId(new IntPtr((long)((DTE2)raw).MainWindow.HWnd), out id);
            if (id == 0) throw new InvalidOperationException("Could not identify XAE host process.");
            return checked((int)id);
        }

        [DllImport("ole32.dll")]
        private static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable table);
        [DllImport("ole32.dll")]
        private static extern int CreateBindCtx(int reserved, out IBindCtx context);

        public static XaeSession[] FindSessions(string progId)
        {
            IRunningObjectTable table;
            IBindCtx context;
            Marshal.ThrowExceptionForHR(GetRunningObjectTable(0, out table));
            Marshal.ThrowExceptionForHR(CreateBindCtx(0, out context));
            IEnumMoniker entries = null;
            var result = new List<XaeSession>();
            try
            {
                table.EnumRunning(out entries);
                var moniker = new IMoniker[1];
                while (entries.Next(1, moniker, IntPtr.Zero) == 0)
                {
                    try
                    {
                        string name;
                        moniker[0].GetDisplayName(context, null, out name);
                        if (name.IndexOf(progId, StringComparison.OrdinalIgnoreCase) < 0) continue;
                        object raw;
                        table.GetObject(moniker[0], out raw);
                        var dte = (DTE2)raw;
                        // Propagate inaccessible matching entries; do not mistake failed inspection for absence.
                        result.Add(new XaeSession { Moniker = name,
                            SolutionPath = dte.Solution.FullName, Projects = ProjectPaths(raw), Dte = raw });
                    }
                    finally { Marshal.ReleaseComObject(moniker[0]); }
                }
                return result.ToArray();
            }
            finally
            {
                if (entries != null) Marshal.ReleaseComObject(entries);
                Marshal.ReleaseComObject(context);
                Marshal.ReleaseComObject(table);
            }
        }

        public static bool IsSaved(object raw)
        {
            var dte = (DTE2)raw;
            if (!dte.Solution.Saved) return false;
            var projects = dte.Solution.Projects;
            for (int i = 1; i <= projects.Count; ++i)
                if (!projects.Item(i).Saved) return false;
            var documents = dte.Documents;
            for (int i = 1; i <= documents.Count; ++i)
                if (!documents.Item(i).Saved) return false;
            return true;
        }

        public static string[] UnsavedItems(object raw)
        {
            var dte = (DTE2)raw;
            var paths = new List<string>();
            if (!dte.Solution.Saved) paths.Add("Solution: " + dte.Solution.FullName);
            var projects = dte.Solution.Projects;
            for (int i = 1; i <= projects.Count; ++i)
                if (!projects.Item(i).Saved) paths.Add("Project: " + projects.Item(i).FullName);
            var documents = dte.Documents;
            for (int i = 1; i <= documents.Count; ++i)
                if (!documents.Item(i).Saved) paths.Add("Document: " + documents.Item(i).FullName);
            return paths.ToArray();
        }

        public static string[] ProjectPaths(object raw)
        {
            var paths = new List<string>();
            var projects = ((DTE2)raw).Solution.Projects;
            for (int i = 1; i <= projects.Count; ++i)
                paths.Add(projects.Item(i).FullName);
            return paths.ToArray();
        }

        public static string[] ProjectNames(object raw)
        {
            var names = new List<string>();
            var projects = ((DTE2)raw).Solution.Projects;
            for (int p = 1; p <= projects.Count; ++p)
            {
                var project = projects.Item(p);
                names.Add(project.Name);
                if (!project.FullName.EndsWith(".tsproj", StringComparison.OrdinalIgnoreCase)) continue;
                var manager = (ITcSysManager)project.Object;
                var plc = manager.LookupTreeItem("TIPC");
                for (int i = 1; i <= plc.ChildCount; ++i)
                    names.Add(plc.get_Child(i).Name);
            }
            return names.ToArray();
        }

        public static object AddProject(object raw, string template, string directory, string name)
        {
            return ((DTE2)raw).Solution.AddFromTemplate(template, directory, name, false);
        }

        public static object SystemManager(object project)
        {
            return ((Project)project).Object;
        }

        public static void SaveProject(object project) { ((Project)project).Save(""); }
        public static object NestedProject(object root)
        {
            return ((ITcProjectRoot)root).NestedProject;
        }

        public static string TreePath(object item) { return ((ITcSmTreeItem)item).PathName; }
        public static bool CheckAll(object project)
        {
            return ((ITcPlcIECProject2)project).CheckAllObjects();
        }

        public static bool Busy(object raw)
        {
            return ((DTE2)raw).Solution.SolutionBuild.BuildState == vsBuildState.vsBuildStateInProgress;
        }

        public static void BeginClean(object raw)
        {
            ((DTE2)raw).Solution.SolutionBuild.Clean(false);
        }

        public static void BeginBuild(object raw, object project)
        {
            // Build the selected TwinCAT project, as in the PC engineering path.
            ((DTE2)raw).Solution.SolutionBuild.BuildProject(Configuration(raw), ((Project)project).FullName, false);
        }

        public static string Configuration(object raw)
        {
            var configuration = (SolutionConfiguration2)((DTE2)raw).Solution.SolutionBuild.ActiveConfiguration;
            return configuration.Name + "|" + configuration.PlatformName;
        }

        public static void SelectConfiguration(object raw, string expected)
        {
            var deadline = DateTime.UtcNow.AddSeconds(30);
            do
            {
                var configurations = ((DTE2)raw).Solution.SolutionBuild.SolutionConfigurations;
                bool ready = configurations.Count > 0;
                for (int i = 1; i <= configurations.Count; ++i)
                {
                    var configuration = configurations.Item(i) as SolutionConfiguration2;
                    if (configuration == null) { ready = false; continue; }
                    if (configuration.Name + "|" + configuration.PlatformName == expected)
                    {
                        configuration.Activate();
                        return;
                    }
                }
                if (ready) throw new InvalidOperationException("Build configuration not found: " + expected);
                System.Threading.Thread.Sleep(250);
            } while (DateTime.UtcNow < deadline);
            throw new InvalidOperationException("XAE did not expose build configurations before the load timeout.");
        }

        public static int LastBuildInfo(object raw)
        {
            return ((DTE2)raw).Solution.SolutionBuild.LastBuildInfo;
        }

        public static void SaveLibrary(object project, string path)
        {
            ((ITcPlcIECProject)project).SaveAsLibrary(path, false);
        }

        public static Diagnostic[] Errors(object raw)
        {
            var dte = (DTE2)raw;
            // Fixed diagnostic-view initialization, matching the established MCP reader.
            dte.ExecuteCommand("View.ErrorList", " ");
            var list = dte.ToolWindows.ErrorList;
            if (list == null) throw new InvalidOperationException("XAE Error List is unavailable.");
            // Materialize the owned host's tool window and include every category.
            // A hidden/uninitialized view can otherwise expose placeholder items.
            list.Parent.Activate();
            list.ShowErrors = true;
            list.ShowWarnings = true;
            list.ShowMessages = true;
            System.Threading.Thread.Sleep(1000);
            var result = new List<Diagnostic>();
            var items = list.ErrorItems;
            for (int i = 1; i <= items.Count; ++i)
            {
                var item = items.Item(i);
                result.Add(new Diagnostic { Severity = item.ErrorLevel.ToString(),
                    Description = item.Description, File = item.FileName,
                    Line = item.Line, Project = item.Project });
            }
            return result.ToArray();
        }

        public static LibraryReference[] References(object item)
        {
            var references = ((ITcPlcLibraryManager)item).References;
            var result = new List<LibraryReference>();
            for (int i = 0; i < references.Count; ++i)
            {
                var reference = references[i];
                var placeholder = reference as ITcPlcPlaceholderRef;
                var library = reference as ITcPlcLibrary;
                if (placeholder != null)
                {
                    library = placeholder.EffectiveResolution;
                    if (library == null) library = placeholder.CurrentLibrary;
                }
                if (library == null)
                    throw new InvalidOperationException("Unresolved library reference: " + reference.Name);
                result.Add(new LibraryReference { Name = reference.Name.TrimStart('#'),
                    Kind = placeholder == null ? "library" : "placeholder",
                    Title = library.Name, Version = library.Version, Company = library.Distributor });
            }
            return result.ToArray();
        }
    }
    [ComImport, Guid("00000016-0000-0000-C000-000000000046"),
        InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IOleMessageFilter
    {
        [PreserveSig] int HandleInComingCall(int type, IntPtr caller, int elapsed, IntPtr info);
        [PreserveSig] int RetryRejectedCall(IntPtr callee, int elapsed, int rejection);
        [PreserveSig] int MessagePending(IntPtr callee, int elapsed, int type);
    }

    // XAE can reject automation calls during loading/building. Retry only rejected
    // calls for a bounded interval on this client thread; never replay an accepted operation.
    public sealed class XaeMessageFilter : IOleMessageFilter
    {
        private static IOleMessageFilter previous;
        private static bool installed;
        [DllImport("ole32.dll")]
        private static extern int CoRegisterMessageFilter(IOleMessageFilter filter, out IOleMessageFilter oldFilter);

        public static void Install()
        {
            if (installed) return;
            Marshal.ThrowExceptionForHR(CoRegisterMessageFilter(new XaeMessageFilter(), out previous));
            installed = true;
        }

        public static void Restore()
        {
            if (!installed) return;
            IOleMessageFilter discarded;
            Marshal.ThrowExceptionForHR(CoRegisterMessageFilter(previous, out discarded));
            installed = false;
            previous = null;
        }

        public int HandleInComingCall(int type, IntPtr caller, int elapsed, IntPtr info) { return 0; }
        public int RetryRejectedCall(IntPtr callee, int elapsed, int rejection)
        {
            return (rejection == 1 || rejection == 2) && elapsed < 30000 ? 250 : -1;
        }
        public int MessagePending(IntPtr callee, int elapsed, int type) { return 2; }
    }

}
