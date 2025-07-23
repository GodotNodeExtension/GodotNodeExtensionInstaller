#!/bin/bash

# GodotNodeExtension Component Installer for Linux/macOS
# Downloads and installs components from GitHub repository with automatic dependency management

# Configuration - Edit these values to set default repository
DEFAULT_GITHUB_REPO="shitake2333/GodotNodeExtension"  # Default GitHub repository
DEFAULT_BRANCH="main"                                 # Default branch to use
USE_LATEST_RELEASE=true                              # Use latest release instead of branch

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_header() {
    echo -e "${MAGENTA}$1${NC}"
}

# Show usage information
show_usage() {
    echo "GodotNodeExtension Component Installer"
    echo "======================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --component NAME    Component name to install"
    echo "  -r, --repo REPO         GitHub repository (default: $DEFAULT_GITHUB_REPO)"
    echo "  -b, --branch BRANCH     Branch to use (default: $DEFAULT_BRANCH)"
    echo "  -p, --path PATH         Godot project path (default: .)"
    echo "  -f, --force             Force overwrite existing component"
    echo "  -s, --skip-deps         Skip dependency installation"
    echo "  -v, --verbose           Verbose output"
    echo "  --from-release          Download from latest release"
    echo "  -l, --list              List available components"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -c DynamicNumberLabel"
    echo "  $0 -c DynamicNumberLabel -r yourname/yourrepo"
    echo "  $0 --list"
    echo "  $0 -c DynamicNumberLabel --from-release"
}

# Parse command line arguments
parse_args() {
    COMPONENT_NAME=""
    GITHUB_REPO="$DEFAULT_GITHUB_REPO"
    BRANCH="$DEFAULT_BRANCH"
    PROJECT_PATH="."
    FORCE=false
    SKIP_DEPENDENCIES=false
    VERBOSE=false
    FROM_RELEASE=false
    LIST_COMPONENTS=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--component)
                COMPONENT_NAME="$2"
                shift 2
                ;;
            -r|--repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            -b|--branch)
                BRANCH="$2"
                shift 2
                ;;
            -p|--path)
                PROJECT_PATH="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -s|--skip-deps)
                SKIP_DEPENDENCIES=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --from-release)
                FROM_RELEASE=true
                shift
                ;;
            -l|--list)
                LIST_COMPONENTS=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if dotnet CLI is available
    if ! command -v dotnet &> /dev/null; then
        print_error ".NET CLI not found. Please install .NET SDK."
        exit 1
    fi
    
    local dotnet_version=$(dotnet --version 2>/dev/null)
    print_success "Found .NET CLI version: $dotnet_version"
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        print_error "Git not found. Please install Git."
        exit 1
    fi
    
    local git_version=$(git --version 2>/dev/null)
    print_success "Found Git: $git_version"
    
    # Check if curl or wget is available
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        print_error "curl or wget not found. Please install one of them."
        exit 1
    fi
    
    # Check if unzip is available (for release downloads)
    if ! command -v unzip &> /dev/null; then
        print_error "unzip not found. Please install unzip."
        exit 1
    fi
    
    # Check if jq is available (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Some features may not work properly. Consider installing jq."
    fi
    
    # Check if project.godot exists
    if [[ ! -f "$PROJECT_PATH/project.godot" ]]; then
        print_error "project.godot not found in '$PROJECT_PATH'. Please specify a valid Godot project path."
        exit 1
    fi
    print_success "Found Godot project at: $PROJECT_PATH"
}

# Download component from GitHub
download_component() {
    local repo_url="$1"
    local component_name="$2"
    local branch="$3"
    local latest_release="$4"
    
    print_info "Downloading component '$component_name' from GitHub..."
    
    local temp_dir=$(mktemp -d)
    local repo_dir="$temp_dir/godot-component-$(date +%s)-$$"
    
    if [[ "$latest_release" == "true" ]]; then
        # Get latest release URL
        local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
        
        print_info "Fetching latest release from: $api_url"
        
        local release_info
        if command -v curl &> /dev/null; then
            release_info=$(curl -s "$api_url")
        else
            release_info=$(wget -qO- "$api_url")
        fi
        
        if [[ -z "$release_info" ]]; then
            print_error "Failed to fetch latest release information"
            rm -rf "$temp_dir"
            exit 1
        fi
        
        local download_url
        if command -v jq &> /dev/null; then
            download_url=$(echo "$release_info" | jq -r '.zipball_url')
            local tag_name=$(echo "$release_info" | jq -r '.tag_name')
            print_info "Downloading from release: $tag_name"
        else
            # Fallback parsing without jq
            download_url=$(echo "$release_info" | grep -o '"zipball_url":"[^"]*"' | cut -d'"' -f4)
            print_info "Downloading from latest release"
        fi
        
        if [[ -z "$download_url" || "$download_url" == "null" ]]; then
            print_error "Failed to get download URL from release"
            rm -rf "$temp_dir"
            exit 1
        fi
        
        # Download and extract
        local zip_path="$temp_dir/component.zip"
        if command -v curl &> /dev/null; then
            curl -L -o "$zip_path" "$download_url"
        else
            wget -O "$zip_path" "$download_url"
        fi
        
        if [[ ! -f "$zip_path" ]]; then
            print_error "Failed to download component archive"
            rm -rf "$temp_dir"
            exit 1
        fi
        
        print_info "Extracting component..."
        unzip -q "$zip_path" -d "$temp_dir"
        
        # Find extracted directory (GitHub format: user-repo-commitid)
        local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "*-*-*" | head -n1)
        if [[ -z "$extracted_dir" ]]; then
            print_error "Failed to find extracted release directory"
            rm -rf "$temp_dir"
            exit 1
        fi
        repo_dir="$extracted_dir"
        
        # Clean up zip file
        rm -f "$zip_path"
    else
        # Clone repository
        print_info "Cloning repository: https://github.com/$GITHUB_REPO.git"
        git clone --depth 1 --branch "$branch" "https://github.com/$GITHUB_REPO.git" "$repo_dir" &>/dev/null
        
        if [[ $? -ne 0 ]]; then
            print_error "Failed to clone repository"
            rm -rf "$temp_dir"
            exit 1
        fi
    fi
    
    # Find component directory
    local component_path="$repo_dir/Component/$component_name"
    if [[ ! -d "$component_path" ]]; then
        print_error "Component '$component_name' not found in repository"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    print_success "Component found at: $component_path"
    echo "$component_path"
}

# Parse component_info.json
get_component_info() {
    local component_path="$1"
    local info_file="$component_path/component_info.json"
    
    if [[ ! -f "$info_file" ]]; then
        print_warning "component_info.json not found. Proceeding without dependency information."
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        local component_name=$(jq -r '.name' "$info_file" 2>/dev/null)
        local component_version=$(jq -r '.version' "$info_file" 2>/dev/null)
        if [[ "$component_name" != "null" && "$component_version" != "null" ]]; then
            print_success "Loaded component info: $component_name v$component_version"
            return 0
        fi
    fi
    
    print_warning "Failed to parse component_info.json"
    return 1
}

# Install component dependencies recursively
install_component_with_dependencies() {
    local component_name="$1"
    local project_path="$2"
    local force="$3"
    local skip_deps="$4"
    local from_release="$5"
    
    local component_path=$(download_component "$GITHUB_REPO" "$component_name" "$BRANCH" "$from_release")
    local info_file="$component_path/component_info.json"
    
    if [[ ! -f "$info_file" ]]; then
        print_error "component_info.json not found for $component_name"
        return 1
    fi
    
    # Install component dependencies first
    if [[ "$skip_deps" != "true" ]] && command -v jq &> /dev/null; then
        local deps=$(jq -r '.dependencies.components[]?' "$info_file" 2>/dev/null)
        if [[ -n "$deps" ]]; then
            while IFS= read -r dep; do
                if [[ -n "$dep" ]]; then
                    print_info "Installing dependency component: $dep"
                    install_component_with_dependencies "$dep" "$project_path" "$force" "$skip_deps" "$from_release"
                fi
            done <<< "$deps"
        fi
    fi
    
    # Install the component itself
    print_info "Installing component: $component_name"
    get_component_info "$component_path"
    install_nuget_dependencies "$component_path" "$project_path"
    install_component_files "$component_path" "$component_name" "$project_path"
}

# Install NuGet dependencies
install_nuget_dependencies() {
    local component_path="$1"
    local project_path="$2"
    local info_file="$component_path/component_info.json"
    
    if [[ "$SKIP_DEPENDENCIES" == "true" ]]; then
        print_info "Skipping dependency installation (--skip-deps specified)"
        return
    fi
    
    if [[ ! -f "$info_file" ]]; then
        print_info "No dependency information found"
        return
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq not available. Skipping automatic dependency installation."
        return
    fi
    
    local has_nuget_deps=$(jq -e '.dependencies.nuget | length > 0' "$info_file" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        print_info "No NuGet dependencies found"
        return
    fi
    
    print_info "Installing NuGet dependencies..."
    
    # Find .csproj file
    local csproj_file=$(find "$project_path" -name "*.csproj" -type f | head -n1)
    if [[ -z "$csproj_file" ]]; then
        print_error "No .csproj file found in project directory"
        exit 1
    fi
    
    print_info "Using project file: $csproj_file"
    
    # Install each package
    local packages=$(jq -r '.dependencies.nuget[] | select(.required != false) | "\(.name)|\(.version // "")"' "$info_file" 2>/dev/null)
    
    while IFS='|' read -r package_name package_version; do
        if [[ -n "$package_name" ]]; then
            if [[ -n "$package_version" ]]; then
                package_version=$(echo "$package_version" | sed 's/>=//g')
                print_info "Installing package: $package_name v$package_version"
                dotnet add "$csproj_file" package "$package_name" --version "$package_version"
            else
                print_info "Installing package: $package_name"
                dotnet add "$csproj_file" package "$package_name"
            fi
            
            if [[ $? -eq 0 ]]; then
                print_success "Installed: $package_name"
            else
                print_warning "Failed to install: $package_name"
            fi
        fi
    done <<< "$packages"
}

# Install component files
install_component_files() {
    local source_path="$1"
    local component_name="$2"
    local project_path="$3"
    
    print_info "Installing component files..."
    
    local target_dir="$project_path/addons/GodotNodeExtension/$component_name"
    
    # Check if component already exists
    if [[ -d "$target_dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            print_warning "Component already exists. Removing existing installation..."
            rm -rf "$target_dir"
        else
            print_error "Component '$component_name' already exists. Use --force to overwrite."
            exit 1
        fi
    fi
    
    # Create target directory
    mkdir -p "$target_dir"
    
    # Copy files (excluding .git directories)
    find "$source_path" -type f ! -path "*/.git/*" | while read -r file; do
        local relative_path="${file#$source_path/}"
        local target_file="$target_dir/$relative_path"
        local target_dir_path=$(dirname "$target_file")
        
        mkdir -p "$target_dir_path"
        cp "$file" "$target_file"
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Copied: $relative_path"
        fi
    done
    
    print_success "Component files installed to: $target_dir"
}

# Build project
build_project() {
    local project_path="$1"
    
    print_info "Building project to generate custom nodes..."
    
    cd "$project_path" || exit 1
    dotnet build --configuration Debug
    
    if [[ $? -eq 0 ]]; then
        print_success "Project built successfully"
    else
        print_warning "Build completed with warnings. Check output above."
    fi
    cd - > /dev/null || exit 1
}

# List available components from COMPONENTS.md
list_components() {
    local repo="$1"
    print_info "Fetching COMPONENTS.md from repository: $repo"
    local url="https://raw.githubusercontent.com/$repo/main/COMPONENTS.md"
    local md_content
    
    if command -v curl &> /dev/null; then
        md_content=$(curl -s "$url")
    else
        md_content=$(wget -qO- "$url")
    fi
    
    if [[ -z "$md_content" ]]; then
        print_warning "COMPONENTS.md is empty or not found."
        return
    fi
    
    print_header ""
    print_header "=== Available Components ==="
    
    local in_table=0
    while IFS= read -r line; do
        if [[ $in_table -eq 0 && $line =~ ^\|.*\|.*\|.*\|.*\|.*\| ]]; then
            in_table=1
            read -r _ # skip separator line
            continue
        fi
        if [[ $in_table -eq 1 ]]; then
            [[ -z "$line" || ! $line =~ ^\| ]] && continue
            IFS='|' read -ra cols <<< "$line"
            if [[ ${#cols[@]} -lt 6 ]]; then continue; fi
            local name=$(echo "${cols[1]}" | xargs)
            local version=$(echo "${cols[2]}" | xargs)
            local author=$(echo "${cols[3]}" | xargs)
            local desc=$(echo "${cols[4]}" | xargs)
            local status=$(echo "${cols[5]}" | xargs)
            [[ -z "$name" ]] && continue
            print_info "• $name (v$version) by $author - $desc [$status]"
        fi
    done <<< "$md_content"
    
    print_header "============================"
}

# Show installation summary
show_installation_summary() {
    local component_info_path="$1"
    local component_name="$2"
    local project_path="$3"
    
    print_header ""
    print_header "=== Installation Summary ==="
    print_success "Component: $component_name"
    
    if [[ -f "$component_info_path/component_info.json" ]] && command -v jq &> /dev/null; then
        local version=$(jq -r '.version' "$component_info_path/component_info.json" 2>/dev/null)
        local description=$(jq -r '.description' "$component_info_path/component_info.json" 2>/dev/null)
        local deps_count=$(jq -r '.dependencies.nuget | length' "$component_info_path/component_info.json" 2>/dev/null)
        
        if [[ "$version" != "null" ]]; then
            print_info "Version: $version"
        fi
        if [[ "$description" != "null" ]]; then
            print_info "Description: $description"
        fi
        if [[ "$deps_count" != "null" && "$deps_count" -gt 0 ]]; then
            print_info "Dependencies installed: $deps_count NuGet packages"
        fi
    fi
    
    print_info "Installation path: $project_path/addons/GodotNodeExtension/$component_name"
    print_success "Installation completed successfully!"
    print_header ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "${WHITE}1. Open your Godot project${NC}"
    echo -e "${WHITE}2. The component will appear in 'Create Node' dialog${NC}"
    echo -e "${WHITE}3. Check the README.md for usage examples${NC}"
}

# Clean up temporary files
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Cleaned up temporary files"
        fi
    fi
}

# Main execution
main() {
    print_header "GodotNodeExtension Component Installer"
    print_header "======================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Handle list components
    if [[ "$LIST_COMPONENTS" == "true" ]]; then
        list_components "$GITHUB_REPO"
        exit 0
    fi
    
    # Validate component name
    if [[ -z "$COMPONENT_NAME" ]]; then
        print_error "Component name is required. Use -c or --component to specify."
        show_usage
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Convert relative path to absolute
    PROJECT_PATH=$(realpath "$PROJECT_PATH")
    
    # Download and install component with dependencies
    local component_path
    component_path=$(install_component_with_dependencies "$COMPONENT_NAME" "$PROJECT_PATH" "$FORCE" "$SKIP_DEPENDENCIES" "$FROM_RELEASE")
    
    # Set up cleanup trap
    TEMP_DIR=$(dirname "$component_path")
    trap cleanup EXIT
    
    # Build project
    build_project "$PROJECT_PATH"
    
    # Show summary
    show_installation_summary "$component_path" "$COMPONENT_NAME" "$PROJECT_PATH"
}

# Handle Ctrl+C gracefully
trap cleanup INT

# Execute main function
main "$@"
