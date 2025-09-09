# GodotNodeExtensionInstaller

A CLI tool for installing, updating, and managing GodotNodeExtension components in your Godot project.

## Features
- Install components from the official repository
- Install NuGet dependencies automatically
- Install example files with `--example` option
- Update all installed components with the `update` command
- Fully supports English output for international use

## Usage

### Install a component
```
GodotNodeExtensionInstaller.exe install <ComponentName> [--example]
```

### Update all components
```
GodotNodeExtensionInstaller.exe update [<ProjectPath>]
```

### List available components
```
GodotNodeExtensionInstaller.exe list
```

### Check environment
```
GodotNodeExtensionInstaller.exe check [<ProjectPath>]
```

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

