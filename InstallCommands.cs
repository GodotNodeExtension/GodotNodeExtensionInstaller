using System.Text.Json;
using ConsoleAppFramework;

struct ComponentInfo
{
    public string Name { get; init; }
    public string Version { get; init; }
    public string Description { get; init; }
    public string Author { get; init; }
    public string License { get; init; }
    public Requirements Requirements { get; init; }
    public Dependencies Dependencies { get; init; }
    public Compatibility Compatibility { get; init; }
}

internal struct Requirements
{
    public string Godot { get; set; }
    public string Dotnet { get; set; }
}

internal struct Dependencies
{
    public NugetPackage[] Nuget { get; set; }
    public string[] Components { get; set; }
}

internal struct NugetPackage
{
    public string Name { get; set; }
    public string Version { get; set; }
    public bool Required { get; set; }
}

internal struct Compatibility
{
    public string[] GodotVersions { get; set; }
    public string[] DotnetVersions { get; set; }
}

public class InstallCommands
{
    public static string InstallRepoPath => "GodotNodeExtension/GodotNodeExtension";
    public static string DotNetVersion => "7.0.0";
    
    /// <summary>
    /// Checks the environment for required dependencies.
    /// </summary>
    [Command("check")]
    public int Check(string path = "")
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("ℹ Checking environment dependencies...");
        Console.ResetColor();
        var allOk = 0;
        if (!CheckDotnet()) allOk = 1;
        if (!CheckGit()) allOk = 1;
        if (string.IsNullOrEmpty(path)) return allOk;
        if (!Directory.Exists(path))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ Folder does not exist: {path}");
            Console.ResetColor();
            allOk = 1;
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"✔ Folder exists: {path}");
            Console.ResetColor();
            var godotProjectFile = Path.Combine(path, "project.godot");
            if (!File.Exists(godotProjectFile))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"❌ Godot project file not found: {godotProjectFile}");
                Console.ResetColor();
                allOk = 1;
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"✔ Godot project file detected: {godotProjectFile}");
                Console.ResetColor();
            }
        }
        return allOk;
    }

    private bool CheckDotnet()
    {
        try
        {
            var dotnetProc = new System.Diagnostics.Process();
            dotnetProc.StartInfo.FileName = "dotnet";
            dotnetProc.StartInfo.Arguments = "--version";
            dotnetProc.StartInfo.RedirectStandardOutput = true;
            dotnetProc.StartInfo.UseShellExecute = false;
            dotnetProc.StartInfo.CreateNoWindow = true;
            dotnetProc.Start();
            var dotnetVersion = dotnetProc.StandardOutput.ReadLine();
            dotnetProc.WaitForExit();
            if (string.IsNullOrEmpty(dotnetVersion))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("❌ .NET SDK not detected. Please install .NET SDK.");
                Console.ResetColor();
                return false;
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"✔ .NET SDK detected: {dotnetVersion}");
                Console.ResetColor();
                if (!IsVersionGreaterOrEqual(dotnetVersion, DotNetVersion))
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"❌ .NET SDK version too low, required >= {DotNetVersion}, current: {dotnetVersion}");
                    Console.ResetColor();
                    return false;
                }
            }
        }
        catch
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("❌ .NET SDK not detected. Please install .NET SDK.");
            Console.ResetColor();
            return false;
        }
        return true;
    }

    private bool CheckGit()
    {
        try
        {
            var gitProc = new System.Diagnostics.Process();
            gitProc.StartInfo.FileName = "git";
            gitProc.StartInfo.Arguments = "--version";
            gitProc.StartInfo.RedirectStandardOutput = true;
            gitProc.StartInfo.UseShellExecute = false;
            gitProc.StartInfo.CreateNoWindow = true;
            gitProc.Start();
            var gitVersion = gitProc.StandardOutput.ReadLine();
            gitProc.WaitForExit();
            if (string.IsNullOrEmpty(gitVersion))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("❌ Git not detected. Please install Git.");
                Console.ResetColor();
                return false;
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"✔ Git detected: {gitVersion}");
                Console.ResetColor();
            }
        }
        catch
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("❌ Git not detected. Please install Git.");
            Console.ResetColor();
            return false;
        }
        return true;
    }

    /// <summary>
    ///  Lists all available components from GitHub repository.
    /// </summary>
    [Command("list")]
    public void List(string repo = "")
    {
        if (string.IsNullOrEmpty(repo)) repo = InstallRepoPath;
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"ℹ Fetching component list from repository: {repo}");
        Console.ResetColor();
        try
        {
            using var client = new HttpClient();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("GodotNodeExtensionInstaller/1.0");
            var url = $"https://api.github.com/repos/{repo}/contents/Component";
            var resp = client.GetAsync(url).Result;
            if (!resp.IsSuccessStatusCode)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"❌ Failed to fetch component list: {resp.StatusCode}");
                Console.ResetColor();
                return;
            }
            var json = resp.Content.ReadAsStringAsync().Result;
            var arr = JsonDocument.Parse(json).RootElement;
            Console.ForegroundColor = ConsoleColor.Magenta;
            Console.WriteLine("=== Available Components ===");
            Console.ResetColor();
            foreach (var item in arr.EnumerateArray())
            {
                if (!item.TryGetProperty("type", out var typeProp) || typeProp.GetString() != "dir") continue;
                var name = item.GetProperty("name").GetString();
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"• {name}");
                Console.ResetColor();
            }
            Console.ForegroundColor = ConsoleColor.Magenta;
            Console.WriteLine("============================");
            Console.ResetColor();
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ Exception while fetching component list: {ex.Message}");
            Console.ResetColor();
        }
    }

    /// <summary>
    /// Installs the specified component from GitHub.
    /// </summary>
    /// <param name="componentName">The name of the component to install.</param>
    /// <param name="projectPath">The path to the Godot project.</param>
    /// <param name="force">Whether to force overwrite if the component already exists.</param>
    /// <param name="skipDependencies">Whether to skip installing dependencies.</param>
    /// <param name="fromRelease">Whether to download from the latest release instead of cloning the repo.</param>
    /// <param name="example">Whether to install example files (if any).</param>
    [Command("install")]
    public void Install(
        [Argument]string componentName,
        [Argument]string projectPath = ".",
        bool force = false,
        bool skipDependencies = false,
        bool fromRelease = false,
        bool example = false)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"ℹ Installing component: {componentName}");
        Console.ResetColor();
        // Check environment
        if (Check(projectPath) != 0)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("❌ Environment check failed. Installation aborted.");
            Console.ResetColor();
            return;
        }
        // Download component
        var tempDir = Path.Combine(Path.GetTempPath(), $"godot-component-{Guid.NewGuid().ToString().Substring(0,8)}");
        var repoUrl = $"https://github.com/{InstallRepoPath}.git";
        const string branch = "main";
        try
        {
            var componentPath = fromRelease ? DownloadComponentFromRelease(InstallRepoPath, componentName, tempDir) : CloneComponentFromRepo(repoUrl, componentName, branch, tempDir);
            if (string.IsNullOrEmpty(componentPath)) throw new Exception("Component download failed");
            // Parse component_info.json
            var info = ParseComponentInfo(componentPath);
            // Install NuGet dependencies
            if (!skipDependencies)
                InstallNugetDependencies(info, projectPath);
            // Recursively install dependency components (if any)
            if (!skipDependencies && info.Dependencies.Components != null)
            {
                foreach (var dep in info.Dependencies.Components)
                {
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine($"⚠ Installing dependency component: {dep}");
                    Console.ResetColor();
                    Install(dep, projectPath, force, skipDependencies, fromRelease, example);
                }
            }
            // Copy component files
            CopyComponentFiles(componentPath, componentName, projectPath, force);
            // If example option is enabled, copy example files from repo/example/{componentName} to project/example/{componentName}
            if (example)
            {
                InstallExampleFiles(componentPath, componentName, projectPath);
            }
            // Installation summary
            ShowInstallSummary(info, componentName, projectPath);
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ Installation failed: {ex.Message}");
            Console.ResetColor();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                try { Directory.Delete(tempDir, true); }
                catch
                {
                    // ignored
                }
            }
        }
    }

    private string DownloadComponentFromRelease(string repoName, string componentName, string tempDir)
    {
        // Get release info
        var apiUrl = $"https://api.github.com/repos/{repoName}/releases/latest";
        using var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("GodotNodeExtensionInstaller/1.0");
        var resp = client.GetAsync(apiUrl).Result;
        if (!resp.IsSuccessStatusCode) throw new Exception("Failed to get release info");
        var releaseInfo = JsonDocument.Parse(resp.Content.ReadAsStringAsync().Result).RootElement;
        var zipUrl = releaseInfo.GetProperty("zipball_url").GetString();
        var zipPath = Path.Combine(tempDir, "component.zip");
        var zipResp = client.GetAsync(zipUrl).Result;
        if (!zipResp.IsSuccessStatusCode) throw new Exception("Failed to download release zip");
        Directory.CreateDirectory(tempDir);
        using (var fs = File.Create(zipPath))
        {
            zipResp.Content.CopyToAsync(fs).Wait();
        }
        System.IO.Compression.ZipFile.ExtractToDirectory(zipPath, tempDir);
        // Find extracted directory
        var dirs = Directory.GetDirectories(tempDir);
        if (dirs.Length == 0) throw new Exception("Extracted directory not found");
        var repoDir = dirs[0];
        var componentDir = Path.Combine(repoDir, "Component", componentName);
        if (!Directory.Exists(componentDir)) throw new Exception($"Component directory not found: {componentDir}");
        return componentDir;
    }

    private string CloneComponentFromRepo(string repoUrl, string componentName, string branch, string tempDir)
    {
        Directory.CreateDirectory(tempDir);
        var repoDir = Path.Combine(tempDir, "repo");
        var proc = new System.Diagnostics.Process();
        proc.StartInfo.FileName = "git";
        proc.StartInfo.Arguments = $"clone --depth 1 --branch {branch} {repoUrl} {repoDir}";
        proc.StartInfo.UseShellExecute = false;
        proc.StartInfo.RedirectStandardOutput = true;
        proc.StartInfo.RedirectStandardError = true;
        proc.StartInfo.CreateNoWindow = true;
        proc.Start();
        proc.WaitForExit();
        if (proc.ExitCode != 0) throw new Exception("git clone failed");
        var componentDir = Path.Combine(repoDir, "Component", componentName);
        if (!Directory.Exists(componentDir)) throw new Exception($"Component directory not found: {componentDir}");
        return componentDir;
    }

    private ComponentInfo ParseComponentInfo(string componentPath)
    {
        var infoFile = Path.Combine(componentPath, "component_info.json");
        if (!File.Exists(infoFile))
        {
            Console.WriteLine("component_info.json not found. Installation failed.");
            throw new FileLoadException("File 'component_info.json' not found!");
        }
        var json = File.ReadAllText(infoFile);
        return JsonSerializer.Deserialize<ComponentInfo>(json);
    }

    private void InstallNugetDependencies(ComponentInfo info, string projectPath)
    {
        if (info.Dependencies.Nuget == null) return;
        var csprojFiles = Directory.GetFiles(projectPath, "*.csproj", SearchOption.AllDirectories);
        if (csprojFiles.Length == 0)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("❌ No .csproj file found. Cannot install NuGet dependencies.");
            Console.ResetColor();
            return;
        }
        var csprojFile = csprojFiles[0];
        foreach (var pkg in info.Dependencies.Nuget)
        {
            if (pkg.Required == false) continue;
            var name = pkg.Name;
            var version = pkg.Version;
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"ℹ Installing NuGet package: {name} {(version != null ? "v" + version : "")}");
            Console.ResetColor();
            var proc = new System.Diagnostics.Process();
            proc.StartInfo.FileName = "dotnet";
            proc.StartInfo.Arguments = version != null ? $"add \"{csprojFile}\" package {name} --version {version.Replace(">=", "")}" : $"add \"{csprojFile}\" package {name}";
            proc.StartInfo.UseShellExecute = false;
            proc.StartInfo.RedirectStandardOutput = true;
            proc.StartInfo.RedirectStandardError = true;
            proc.StartInfo.CreateNoWindow = true;
            proc.Start();
            proc.WaitForExit();
            if (proc.ExitCode == 0)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"✔ Installed: {name}");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"⚠ Failed to install: {name}");
                Console.ResetColor();
            }
        }
    }
    
    private void CopyComponentFiles(string sourcePath, string componentName, string projectPath, bool force)
    {
        var targetDir = Path.Combine(projectPath, "addons", "GodotNodeExtension", componentName);
        if (Directory.Exists(targetDir))
        {
            if (force)
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"⚠ Component already exists. Overwriting: {targetDir}");
                Console.ResetColor();
                Directory.Delete(targetDir, true);
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"❌ Component '{componentName}' already exists. Use --force to overwrite.");
                Console.ResetColor();
                throw new Exception("Component already exists");
            }
        }
        Directory.CreateDirectory(targetDir);
        foreach (var file in Directory.GetFiles(sourcePath, "*", SearchOption.AllDirectories))
        {
            if (file.Contains(".git")) continue;
            var relPath = file.Substring(sourcePath.Length).TrimStart(Path.DirectorySeparatorChar);
            var destFile = Path.Combine(targetDir, relPath);
            var destDir = Path.GetDirectoryName(destFile);
            if (!Directory.Exists(destDir))
                if (destDir != null)
                    Directory.CreateDirectory(destDir);
            File.Copy(file, destFile, true);
        }
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"✔ Component files installed to: {targetDir}");
        Console.ResetColor();
    }
    
    private void InstallExampleFiles(string repoComponentPath, string componentName, string projectPath)
    {
        // repoComponentPath: path to the component folder in the temp repo
        // componentName: name of the component
        // projectPath: target Godot project path
        var repoExampleDir = Path.Combine(Path.GetDirectoryName(repoComponentPath) ?? string.Empty, "..", "..", "Example", componentName);
        repoExampleDir = Path.GetFullPath(repoExampleDir);
        var targetExampleDir = Path.Combine(projectPath, "example", componentName);
        if (Directory.Exists(repoExampleDir))
        {
            Directory.CreateDirectory(targetExampleDir);
            foreach (var file in Directory.GetFiles(repoExampleDir, "*", SearchOption.AllDirectories))
            {
                var relPath = file.Substring(repoExampleDir.Length).TrimStart(Path.DirectorySeparatorChar);
                var destFile = Path.Combine(targetExampleDir, relPath);
                var destDir = Path.GetDirectoryName(destFile);
                if (!Directory.Exists(destDir) && destDir != null)
                    Directory.CreateDirectory(destDir);
                File.Copy(file, destFile, true);
            }
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"✔ Example files installed to: {targetExampleDir}");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"⚠ No example found for component: {componentName}");
            Console.ResetColor();
        }
    }
    
    private void ShowInstallSummary(ComponentInfo info, string componentName, string projectPath)
    {
        Console.ForegroundColor = ConsoleColor.Magenta;
        Console.WriteLine("\n=== Installation Summary ===");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"Component: {componentName}");
        Console.ResetColor();
        if (!string.IsNullOrEmpty(info.Version))
        {
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"Version: {info.Version}");
            Console.ResetColor();
        }
        if (!string.IsNullOrEmpty(info.Description))
        {
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"Description: {info.Description}");
            Console.ResetColor();
        }
        if (info.Dependencies.Nuget != null)
        {
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"NuGet dependencies installed: {info.Dependencies.Nuget.Length}");
            Console.ResetColor();
        }
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"Install path: {Path.Combine(projectPath, "addons", "GodotNodeExtension", componentName)}");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine("✓ Installation completed!");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine("Next steps:");
        Console.WriteLine("1. Open your Godot project");
        Console.WriteLine("2. The component will appear in the 'Create Node' dialog");
        Console.WriteLine("3. Check README.md for usage examples");
        Console.ResetColor();
    }
    
    private bool IsVersionGreaterOrEqual(string actual, string required)
    {
        try
        {
            var actualParts = actual.Split('.');
            var requiredParts = required.Split('.');
            for (var i = 0; i < requiredParts.Length; i++)
            {
                var a = i < actualParts.Length ? int.Parse(actualParts[i]) : 0;
                var r = int.Parse(requiredParts[i]);
                if (a > r) return true;
                if (a < r) return false;
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Updates all installed components in the specified Godot project path.
    /// </summary>
    /// <param name="path">The path to the Godot project (default: current directory).</param>
    [Command("update")]
    public void Update(string path = ".")
    {
        var addonsDir = Path.Combine(path, "addons", "GodotNodeExtension");
        if (!Directory.Exists(addonsDir))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ No components found in: {addonsDir}");
            Console.ResetColor();
            return;
        }
        var componentDirs = Directory.GetDirectories(addonsDir);
        if (componentDirs.Length == 0)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"⚠ No components installed in: {addonsDir}");
            Console.ResetColor();
            return;
        }
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"ℹ Updating components in: {addonsDir}");
        Console.ResetColor();
        foreach (var compDir in componentDirs)
        {
            var componentName = Path.GetFileName(compDir);
            Console.ForegroundColor = ConsoleColor.Magenta;
            Console.WriteLine($"→ Updating component: {componentName}");
            Console.ResetColor();
            try
            {
                Install(componentName, path, force: true);
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"❌ Failed to update {componentName}: {ex.Message}");
                Console.ResetColor();
            }
        }
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine("✓ All components update process finished.");
        Console.ResetColor();
    }
}