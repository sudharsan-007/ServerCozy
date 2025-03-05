# ServerCozy 🏡☁️ v1.9.0

> Make yourself at home in the cloud, instantly.

![License](https://img.shields.io/github/license/sudharsan-007/servercozy)
![Bash](https://img.shields.io/badge/shell-bash-brightgreen)
![Version](https://img.shields.io/badge/version-1.9.0-blue)

ServerCozy is a script designed to transform bare cloud servers and local environments into comfortable, productive workspaces. It automates the installation of essential tools, configures helpful aliases, and enhances your terminal experience - making any system feel like home in minutes.

## Overview

Moving into a new server or setting up a new system should feel like coming home. ServerCozy automates the setup process by:

- Installing carefully selected tools and utilities
- Configuring a beautiful, informative shell prompt
- Setting up productivity-enhancing aliases
- Customizing vim and other tools with sensible defaults
- Supporting multiple operating systems automatically
- Providing robust error handling and self-recovery

## Features

- **Cross-Platform Compatibility**
  - Supports Ubuntu, Debian, CentOS, Fedora, Red Hat, Alpine Linux, macOS, and BSD variants
  - Windows Subsystem for Linux (WSL) detection and support
  - Automatically uses the appropriate package manager (apt, yum/dnf, apk, brew, pacman, pkg)
  - Fall back to user-level installations when system-wide access isn't available

- **Three-Tier Package Installation**
  - **Essential Tools**: git, curl, wget, htop, tree, unzip, vim, tmux
  - **Recommended Tools**: eza (modern ls, successor to exa), bat (better cat), ncdu, tldr, jq, fzf, pfetch (system info)
  - **Advanced Tools**: ripgrep, fd, neofetch, micro, zoxide, btop

- **Self-Updating Mechanism**
  - Automatically checks for script updates
  - Seamlessly updates to the latest version
  - Creates backups of the previous version

- **Robust Error Handling**
  - Automatic backup and restore for modified config files
  - Detailed error reporting with line numbers and command context
  - Graceful failure recovery

- **Terminal Improvements**
  - Installs JetBrainsMono Nerd Font for improved terminal display
  - Shell-specific optimized configurations:
    - Bash: Enhanced prompt with git integration and dynamic path handling
    - ZSH: Custom prompt with vcs_info integration and clean visuals
  - Intelligent terminal detection and adaptation
  - Sets up color support and useful icons

- **Productivity Enhancements**
  - Creates helpful aliases like `sysinfo` and `repofetch`
  - OS-aware system information display
  - Configures vim with sensible defaults, key mappings, and syntax highlighting
  - Intelligent PATH management for user-installed binaries
  - Sets up tmux for session management

- **User Experience**
  - Interactive installation with multiple UI options (dialog TUI or text-based)
  - Progress reporting with elapsed time tracking
  - Detailed logging for troubleshooting
  - Lock file mechanism to prevent multiple simultaneous runs

## Installation

### Quick Install

```bash
# Download ServerCozy to your server
curl -o ~/server-cozy.sh https://raw.githubusercontent.com/sudharsan-007/servercozy/main/server-cozy.sh
chmod +x ~/server-cozy.sh

# Run it
./server-cozy.sh
```

### Manual Installation

Clone the repository:

```bash
git clone https://github.com/sudharsan-007/servercozy.git
cd servercozy
chmod +x server-cozy.sh
./server-cozy.sh
```

## Usage

```bash
# Interactive installation (recommended for first-time use)
./server-cozy.sh

# Install only essential tools
./server-cozy.sh --essential-only

# Non-interactive mode with default selections
./server-cozy.sh --non-interactive

# Skip system-wide installations, use user directories only
./server-cozy.sh --user-only

# Force text-based interface (don't use dialog TUI)
./server-cozy.sh --no-dialog

# Skip checking for script updates
./server-cozy.sh --skip-update

# Display version information
./server-cozy.sh -v

# Show help
./server-cozy.sh --help
```

## Tool Categories

### Essential Tools

| Tool | Description |
|------|-------------|
| git | Version control system |
| curl | Command line tool for transferring data |
| wget | Network utility to retrieve files from the web |
| htop | Interactive process viewer |
| tree | Directory listing in tree format |
| unzip | Extract ZIP archives |
| vim | Highly configurable text editor |
| tmux | Terminal multiplexer |

### Recommended Tools

| Tool | Description |
|------|-------------|
| eza | Modern replacement for ls (successor to exa) |
| bat | Cat clone with syntax highlighting |
| ncdu | Disk usage analyzer with ncurses interface |
| tldr | Simplified man pages |
| jq | Lightweight and flexible command-line JSON processor |
| fzf | Command-line fuzzy finder |
| pfetch | Simple system information tool |

### Advanced Tools

| Tool | Description |
|------|-------------|
| ripgrep | Line-oriented search tool (rg) |
| fd | Simple, fast alternative to find |
| neofetch | Command-line system information tool |
| micro | Modern and intuitive terminal-based text editor |
| zoxide | Smarter cd command (z) |
| btop | Resource monitor showing CPU, memory, network, and storage |

## Shell Customizations

### Custom Prompt

ServerCozy installs a beautiful and informative prompt that shows:

- Username and hostname
- Current directory (shortened if too long)
- Git branch and status (when in a git repository)
- Color-coded status indicator

### Useful Aliases

```bash
# Navigation
alias ..='cd ..'
alias ...='cd ../..'

# Enhanced commands
alias ls='eza --icons'  # If eza is installed
alias ll='eza -alF --icons'
alias lt='eza -T --icons'
# Backward compatibility for exa also supported
alias cat='bat'  # If bat is installed

# System information
alias sysinfo='pfetch'  # If pfetch is installed, otherwise falls back to a custom display

# Git repositories status
alias repofetch='find . -maxdepth 3 -type d -name ".git" | while read dir; do cd $(dirname $dir) && echo -e "\033[1;36m$(basename $(pwd))\033[0m: $(git branch --show-current) [$(git config --get remote.origin.url 2>/dev/null || echo "No remote")]" && cd - > /dev/null; done'

# Server management
alias ports='netstat -tulanp'
alias meminfo='free -m -l -t'
```

### Vim Configuration

ServerCozy sets up vim with developer-friendly defaults:

- Syntax highlighting and color schemes
- Line numbers and ruler
- Search highlighting with smart case sensitivity
- Tab settings (2 spaces) with proper indentation
- Improved status line with file information
- Full mouse support in terminal
- Better backspace behavior
- Extended command history
- Convenient key mappings for navigation
- Support for file type detection and plugins

## Example Use Cases

### New Server Setup

When you've just created a new cloud server:

```bash
# 1. SSH into your new server
ssh user@your-server-ip

# 2. Download and run ServerCozy
curl -o server-cozy.sh https://raw.githubusercontent.com/sudharsan-007/servercozy/main/server-cozy.sh
chmod +x server-cozy.sh
./server-cozy.sh

# 3. Either log out and back in, or source your bash/zsh config
source ~/.bashrc

# 4. Enjoy your enhanced environment!
sysinfo
```

### Existing Server Enhancement

Improve the comfort and productivity of servers you already use:

```bash
# Choose which enhancements you want
./server-cozy.sh

# Or just get the essential tools
./server-cozy.sh --essential-only
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by countless hours of repetitive server setup
- Thanks to all the amazing open-source tools this project builds upon