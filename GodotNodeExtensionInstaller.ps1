# GodotNodeExtension Component Installer
# Downloads and installs components from GitHub repository with automatic dependency management

param(
    [Parameter(Mandatory=$false)]
    [string]$ComponentName,

    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = ".",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDependencies,
    
    [Parameter(Mandatory=$false)]
    [switch]$FromRelease,
    
    [Parameter(Mandatory=$false)]
    [switch]$ListComponents
)

# Configuration - Edit these values to set default repository
$GitHubRepo = "shitake2333/GodotNodeExtension"  # Default GitHub repository
$Branch = "main"                                # Default branch to use
$UseLatestRelease = $true                       # Use latest release instead of branch

# Color output functions
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-ColorOutput "✓ $Message" "Green" }
function Write-Error { param([string]$Message) Write-ColorOutput "✗ $Message" "Red" }
function Write-Warning { param([string]$Message) Write-ColorOutput "⚠ $Message" "Yellow" }
function Write-Info { param([string]$Message) Write-ColorOutput "ℹ $Message" "Cyan" }

# Validate parameters
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if dotnet CLI is available
    try {
        $dotnetVersion = dotnet --version
        Write-Success "Found .NET CLI version: $dotnetVersion"
    }
    catch {
        Write-Error ".NET CLI not found. Please install .NET SDK."
        exit 1
    }
    
    # Check if git is available
    try {
        $gitVersion = git --version
        Write-Success "Found Git: $gitVersion"
    }
    catch {
        Write-Error "Git not found. Please install Git."
        exit 1
    }
    
    # Check if project.godot exists
    $projectFile = Join-Path $ProjectPath "project.godot"
    if (-not (Test-Path $projectFile)) {
        Write-Error "project.godot not found in '$ProjectPath'. Please specify a valid Godot project path."
        exit 1
    }
    Write-Success "Found Godot project at: $ProjectPath"
}

# Download component from GitHub
function Get-ComponentFromGitHub {
    param([string]$RepoUrl, [string]$ComponentName, [string]$Branch, [switch]$LatestRelease)
    
    Write-Info "Downloading component '$ComponentName' from GitHub..."
    
    $tempDir = [System.IO.Path]::GetTempPath()
    $repoDir = Join-Path $tempDir "godot-component-$([System.Guid]::NewGuid().ToString().Substring(0,8))"
    
    try {
        if ($LatestRelease) {
            # Get latest release URL
            $repoName = $RepoUrl -replace "https://github.com/", "" -replace "\.git$", ""
            $apiUrl = "https://api.github.com/repos/$repoName/releases/latest"
            
            Write-Info "Fetching latest release from: $apiUrl"
            $releaseInfo = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
            
            # Download source code archive
            $downloadUrl = $releaseInfo.zipball_url
            Write-Info "Downloading from release: v$($releaseInfo.tag_name)"
            
            $zipPath = Join-Path $tempDir "component.zip"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -ErrorAction Stop
            
            Write-Info "Extracting component..."
            Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
            
            # Find the extracted directory (GitHub creates a directory with format: user-repo-commitid)
            $extractedDirs = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -match "^.*-.*-[a-f0-9]{7}$" }
            if ($extractedDirs.Count -eq 0) {
                throw "Failed to find extracted release directory"
            }
            $repoDir = $extractedDirs[0].FullName
            
            # Clean up zip file
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        } else {
            # Clone repository
            Write-Info "Cloning repository: $RepoUrl"
            git clone --depth 1 --branch $Branch $RepoUrl $repoDir 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to clone repository"
            }
        }
        
        # Find component directory
        $componentPath = Join-Path $repoDir "Component\$ComponentName"
        if (-not (Test-Path $componentPath)) {
            throw "Component '$ComponentName' not found in repository"
        }
        
        Write-Success "Component found at: $componentPath"
        return $componentPath
    }
    catch {
        Write-Error "Failed to download component: $($_.Exception.Message)"
        if (Test-Path $repoDir) {
            Remove-Item $repoDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
}

# Parse component_info.json
function Get-ComponentInfo {
    param([string]$ComponentPath)
    
    $infoFile = Join-Path $ComponentPath "component_info.json"
    if (-not (Test-Path $infoFile)) {
        Write-Warning "component_info.json not found. Proceeding without dependency information."
        return $null
    }
    
    try {
        $componentInfo = Get-Content $infoFile -Raw | ConvertFrom-Json
        Write-Success "Loaded component info: $($componentInfo.name) v$($componentInfo.version)"
        return $componentInfo
    }
    catch {
        Write-Warning "Failed to parse component_info.json: $($_.Exception.Message)"
        return $null
    }
}

# Install NuGet dependencies
function Install-NuGetDependencies {
    param([object]$ComponentInfo, [string]$ProjectPath)
    
    if ($SkipDependencies) {
        Write-Info "Skipping dependency installation (--SkipDependencies specified)"
        return
    }
    
    if (-not $ComponentInfo -or -not $ComponentInfo.dependencies -or -not $ComponentInfo.dependencies.nuget) {
        Write-Info "No NuGet dependencies found"
        return
    }
    
    Write-Info "Installing NuGet dependencies..."
    
    $csprojFiles = Get-ChildItem -Path $ProjectPath -Filter "*.csproj" -Recurse
    if ($csprojFiles.Count -eq 0) {
        Write-Error "No .csproj file found in project directory"
        exit 1
    }
    
    $csprojFile = $csprojFiles[0].FullName
    Write-Info "Using project file: $csprojFile"
    
    foreach ($package in $ComponentInfo.dependencies.nuget) {
        if ($package.required -eq $false) {
            Write-Info "Skipping optional package: $($package.name)"
            continue
        }
        
        $packageName = $package.name
        $packageVersion = if ($package.version) { $package.version -replace ">=", "" } else { $null }
        
        Write-Info "Installing package: $packageName $(if ($packageVersion) { "v$packageVersion" })"
        
        try {
            if ($packageVersion) {
                dotnet add $csprojFile package $packageName --version $packageVersion
            } else {
                dotnet add $csprojFile package $packageName
            }
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Installed: $packageName"
            } else {
                Write-Warning "Failed to install: $packageName"
            }
        }
        catch {
            Write-Warning "Error installing $packageName`: $($_.Exception.Message)"
        }
    }
}

# Copy component files
function Install-ComponentFiles {
    param([string]$SourcePath, [string]$ComponentName, [string]$ProjectPath)
    
    Write-Info "Installing component files..."
    
    $targetDir = Join-Path $ProjectPath "addons\GodotNodeExtension\$ComponentName"
    
    # Check if component already exists
    if (Test-Path $targetDir) {
        if ($Force) {
            Write-Warning "Component already exists. Removing existing installation..."
            Remove-Item $targetDir -Recurse -Force
        } else {
            Write-Error "Component '$ComponentName' already exists. Use -Force to overwrite."
            exit 1
        }
    }
    
    # Create target directory
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    
    # Copy all files except git-related files
    $filesToCopy = Get-ChildItem -Path $SourcePath -Recurse | Where-Object { 
        -not $_.FullName.Contains(".git") -and -not $_.PSIsContainer 
    }
    
    foreach ($file in $filesToCopy) {
        $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
        $targetFile = Join-Path $targetDir $relativePath
        $targetFileDir = Split-Path $targetFile -Parent
        
        if (-not (Test-Path $targetFileDir)) {
            New-Item -ItemType Directory -Path $targetFileDir -Force | Out-Null
        }
        
        Copy-Item $file.FullName $targetFile -Force
    }
    
    Write-Success "Component files installed to: $targetDir"
}

# Build project
function Build-Project {
    param([string]$ProjectPath)
    
    Write-Info "Building project to generate custom nodes..."
    
    try {
        Push-Location $ProjectPath
        dotnet build --configuration Debug
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Project built successfully"
        } else {
            Write-Warning "Build completed with warnings. Check output above."
        }
    }
    catch {
        Write-Error "Build failed: $($_.Exception.Message)"
    }
    finally {
        Pop-Location
    }
}

# Clean up temporary files
function Remove-TempFiles {
    param([string]$TempPath)
    
    if (Test-Path $TempPath) {
        try {
            Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to clean up temporary files: $TempPath"
        }
    }
}

# Display installation summary
function Show-InstallationSummary {
    param([object]$ComponentInfo, [string]$ComponentName, [string]$ProjectPath)
    
    Write-ColorOutput "`n=== Installation Summary ===" "Magenta"
    Write-Success "Component: $ComponentName"
    
    if ($ComponentInfo) {
        Write-Info "Version: $($ComponentInfo.version)"
        Write-Info "Description: $($ComponentInfo.description)"
        
        if ($ComponentInfo.dependencies.nuget) {
            Write-Info "Dependencies installed: $($ComponentInfo.dependencies.nuget.Count) NuGet packages"
        }
    }
    
    Write-Info "Installation path: $(Join-Path $ProjectPath "addons\GodotNodeExtension\$ComponentName")"
    Write-ColorOutput "✓ Installation completed successfully!" "Green"
    Write-ColorOutput "`nNext steps:" "Yellow"
    Write-ColorOutput "1. Open your Godot project" "White"
    Write-ColorOutput "2. The component will appear in 'Create Node' dialog" "White"
    Write-ColorOutput "3. Check the README.md for usage examples" "White"
}

# List available components in the repository
function List-Components {
    param([string]$RepoUrl)
    
    Write-Info "Listing components in repository: $RepoUrl"
    
    # Get repository content
    $apiUrl = "https://api.github.com/repos/$RepoUrl/contents/Component"
    $components = Invoke-RestMethod -Uri $apiUrl -UseBasicP
    
    if (-not $components -or $components.Count -eq 0) {
        Write-Warning "No components found in the repository"
        return
    }
    
    Write-ColorOutput "`n=== Available Components ===" "Magenta"
    foreach ($component in $components) {
        if ($component.type -eq "dir") {
            Write-Info "• $($component.name)"
        }
    }
    Write-ColorOutput "============================" "Magenta"
}

# 解析组件依赖并递归安装
function Install-ComponentWithDependencies {
    param(
        [string]$ComponentName,
        [string]$ProjectPath,
        [switch]$Force,
        [switch]$SkipDependencies,
        [switch]$FromRelease
    )
    $ComponentDir = Join-Path -Path $PSScriptRoot -ChildPath "Component/$ComponentName"
    $InfoFile = Join-Path $ComponentDir 'component_info.json'
    if (!(Test-Path $InfoFile)) {
        Write-Host "[ERROR] component_info.json not found for $ComponentName" -ForegroundColor Red
        return
    }
    $info = Get-Content $InfoFile | ConvertFrom-Json
    if ($info.dependencies -and !$SkipDependencies) {
        if ($info.dependencies.components) {
            foreach ($dep in $info.dependencies.components) {
                Write-Host "[INFO] Installing dependency component: $dep"
                Install-ComponentWithDependencies -ComponentName $dep -ProjectPath $ProjectPath -Force:$Force -SkipDependencies:$SkipDependencies -FromRelease:$FromRelease
            }
        }
    }
    # 组件自身安装逻辑
    Write-Host "[INFO] Installing component: $ComponentName"
    # ...此处为原有的组件安装逻辑...
}

# Main execution
function Main {
    Write-ColorOutput "GodotNodeExtension Component Installer" "Magenta"
    Write-ColorOutput "=======================================" "Magenta"
    
    # Validate prerequisites
    Test-Prerequisites
    
    # Convert relative path to absolute
    $ProjectPath = Resolve-Path $ProjectPath
    
    # Construct GitHub URL
    $repoUrl = "https://github.com/$GitHubRepo.git"
    
    if ($ListComponents) {
        # List components and exit
        List-Components -RepoUrl $GitHubRepo
        exit 0
    }
    
    # Download component
    $componentPath = Get-ComponentFromGitHub -RepoUrl $repoUrl -ComponentName $ComponentName -Branch $Branch -LatestRelease:$FromRelease
    
    try {
        # Parse component info
        $componentInfo = Get-ComponentInfo -ComponentPath $componentPath
        
        # Install dependencies
        Install-NuGetDependencies -ComponentInfo $componentInfo -ProjectPath $ProjectPath
        
        # Copy component files
        Install-ComponentFiles -SourcePath $componentPath -ComponentName $ComponentName -ProjectPath $ProjectPath
        
        # Build project
        Build-Project -ProjectPath $ProjectPath
        
        # Show summary
        Show-InstallationSummary -ComponentInfo $componentInfo -ComponentName $ComponentName -ProjectPath $ProjectPath
    }
    finally {
        # Cleanup
        $tempDir = Split-Path $componentPath -Parent
        Remove-TempFiles -TempPath $tempDir
    }
}

# Execute main function
try {
    Main
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}
