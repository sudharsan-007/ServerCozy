#!/bin/bash
#
# server-cozy.sh - ServerCozy
#
# This script enhances a cloud server environment with useful tools and configurations.
# It automates the installation of common utilities, shell improvements, and productivity tools.
#
# Author: Sudharsan Ananth
# Version: 1.0.0
# Created: February 2025
#
# Usage:
#   ./server-cozy.sh [OPTIONS]
#
# Options:
#   --non-interactive    Run with default selections
#   --essential-only     Install only essential tools
#   --help               Show this help message
#
# Examples:
#   ./server-cozy.sh
#   ./server-cozy.sh --essential-only

set -e

# Script version
VERSION="1.0.0"

# Default values
INTERACTIVE=true
INSTALL_ESSENTIALS=true
INSTALL_RECOMMENDED=true
INSTALL_ADVANCED=false
INSTALL_NERD_FONT=true
CONFIGURE_PROMPT=true
CONFIGURE_ALIASES=true
CONFIGURE_VIM=true
LOG_FILE="/tmp/servercozy-$(date +%Y%m%d%H%M%S).log"
# Array to store selected packages
declare -a SELECTED_PACKAGES

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Tool categories with descriptions
ESSENTIAL_TOOLS=(
  "git:Version control system"
  "curl:Command line tool for transferring data with URL syntax"
  "wget:Network utility to retrieve files from the web"
  "htop:Interactive process viewer"
  "tree:Directory listing in tree format"
  "unzip:List, test and extract compressed files in a ZIP archive"
  "vim:Highly configurable text editor"
  "tmux:Terminal multiplexer"
)

RECOMMENDED_TOOLS=(
  "exa:Modern replacement for ls"
  "bat:Cat clone with syntax highlighting"
  "ncdu:Disk usage analyzer with ncurses interface"
  "tldr:Simplified man pages"
  "jq:Lightweight and flexible command-line JSON processor"
  "fzf:Command-line fuzzy finder"
  "pfetch:Simple system information tool"
)

ADVANCED_TOOLS=(
  "ripgrep:Line-oriented search tool (rg)"
  "fd:Simple, fast, and user-friendly alternative to find"
  "neofetch:Command-line system information tool"
  "micro:Modern and intuitive terminal-based text editor"
  "zoxide:Smarter cd command (z)"
  "btop:Resource monitor that shows usage and stats for CPU, memory, network and storage"
)

# Function to display help
show_help() {
  echo -e "${BLUE}${BOLD}ServerCozy v${VERSION}${NC}"
  echo
  echo "This script enhances a cloud server environment with useful tools and configurations."
  echo "It automates the installation of common utilities, shell improvements, and productivity tools."
  echo
  echo -e "${YELLOW}${BOLD}Usage:${NC}"
  echo "  ./server-cozy.sh [OPTIONS]"
  echo
  echo -e "${YELLOW}${BOLD}Options:${NC}"
  echo "  --non-interactive    Run with default selections"
  echo "  --essential-only     Install only essential tools"
  echo "  --help               Show this help message"
  echo
  echo -e "${YELLOW}${BOLD}Examples:${NC}"
  echo "  ./server-cozy.sh"
  echo "  ./server-cozy.sh --essential-only"
  echo
}

# Function to log messages
log() {
  local level="$1"
  local message="$2"
  local color=""
  
  case "$level" in
    "ERROR") color="$RED" ;;
    "WARNING") color="$YELLOW" ;;
    "INFO") color="$BLUE" ;;
    "SUCCESS") color="$GREEN" ;;
    *) color="$NC" ;;
  esac
  
  # Print to console with color
  echo -e "${color}[$level] $message${NC}"
  
  # Log to file without color codes
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# Function to detect operating system
detect_os() {
  log "INFO" "Detecting operating system..."
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
    OS_VERSION=$VERSION_ID
    
    if [[ $OS_NAME == *"Ubuntu"* ]] || [[ $OS_NAME == *"Debian"* ]]; then
      OS_TYPE="debian"
      PKG_MANAGER="apt"
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    elif [[ $OS_NAME == *"CentOS"* ]] || [[ $OS_NAME == *"Red Hat"* ]] || [[ $OS_NAME == *"Fedora"* ]]; then
      OS_TYPE="redhat"
      if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    elif [[ $OS_NAME == *"Alpine"* ]]; then
      OS_TYPE="alpine"
      PKG_MANAGER="apk"
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    else
      log "WARNING" "Unsupported distribution: ${OS_NAME}. Will try using apt."
      OS_TYPE="unknown"
      PKG_MANAGER="apt"
    fi
  else
    log "ERROR" "Could not detect operating system!"
    exit 1
  fi
}

# Function to update package repositories
update_package_repos() {
  log "INFO" "Updating package repositories..."
  
  case $PKG_MANAGER in
    apt)
      sudo apt update -y
      ;;
    dnf|yum)
      sudo $PKG_MANAGER check-update -y
      ;;
    apk)
      sudo apk update
      ;;
  esac
  
  log "SUCCESS" "Package repositories updated."
}

# Function to check if a package is installed
is_installed() {
  local package_name="$1"
  
  case $PKG_MANAGER in
    apt)
      dpkg -l | grep -q "ii  $package_name "
      ;;
    dnf|yum)
      rpm -q "$package_name" &>/dev/null
      ;;
    apk)
      apk info -e "$package_name" &>/dev/null
      ;;
    *)
      command -v "$package_name" &>/dev/null
      ;;
  esac
}

# Function to install a package
install_package() {
  local package="$1"
  local description="$2"
  
  # Extract the first word before a colon if it exists
  local package_name="${package%%:*}"
  
  if is_installed "$package_name"; then
    log "INFO" "$package_name is already installed."
    return 0
  fi
  
  # Skip standard installation for pfetch - it will be handled in handle_special_packages
  if [ "$package_name" = "pfetch" ]; then
    log "INFO" "Skipping standard installation for pfetch. Will install from GitHub later."
    return 0
  fi
  
  log "INFO" "Installing $package_name ($description)..."
  
  case $PKG_MANAGER in
    apt)
      sudo apt install -y "$package_name"
      ;;
    dnf|yum)
      sudo $PKG_MANAGER install -y "$package_name"
      ;;
    apk)
      sudo apk add "$package_name"
      ;;
  esac
  
  if is_installed "$package_name"; then
    log "SUCCESS" "$package_name installed successfully."
    return 0
  else
    log "ERROR" "Failed to install $package_name."
    return 1
  fi
}

# Function to detect terminal capabilities
check_terminal_capabilities() {
  # Check if tput works with this terminal
  if tput sc >/dev/null 2>&1 && tput rc >/dev/null 2>&1 && tput ed >/dev/null 2>&1 && tput civis >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to create an interactive selection menu with arrow keys and spacebar
interactive_menu() {
  local -n items=$1        # Reference to array of items to display
  local -n selected=$2     # Reference to array to store selected indexes
  local title=$3           # Title to display
  local default_state=$4   # Default selection state (true/false)
  
  # Clear the array for storing selected indexes
  selected=()
  
  # Initialize with default selection state if provided
  if [ "$default_state" = true ]; then
    for i in "${!items[@]}"; do
      selected+=($i)
    done
  fi
  
  # Check if we can use advanced terminal features
  if ! check_terminal_capabilities; then
    log "WARNING" "Your terminal doesn't support advanced features. Using simplified menu instead."
    basic_interactive_menu items selected "$title" "$default_state"
    return
  fi
  
  # Terminal control sequences
  local ESC=$'\e'
  local cursor_pos=0
  local key
  local menu_size=${#items[@]}
  
  # Save cursor position and disable cursor (with error suppression)
  tput sc >/dev/null 2>&1
  tput civis >/dev/null 2>&1
  
  # Set terminal to raw mode (with error suppression)
  stty -echo raw 2>/dev/null
  
  # Render menu function
  render_menu() {
    # Clear previous menu (move to saved position and clear below)
    tput rc >/dev/null 2>&1
    tput ed >/dev/null 2>&1
    
    echo -e "${BOLD}${title}${NC}"
    
    for i in "${!items[@]}"; do
      IFS=':' read -r pkg desc <<< "${items[$i]}"
      
      # Draw selected/unselected box and highlight current position
      if [[ " ${selected[*]} " =~ " $i " ]]; then
        if [ "$i" -eq "$cursor_pos" ]; then
          echo -e " ${CYAN}${BOLD}→${NC} [${GREEN}x${NC}] ${BOLD}$pkg${NC} - $desc"
        else
          echo -e "   [${GREEN}x${NC}] ${BOLD}$pkg${NC} - $desc"
        fi
      else
        if [ "$i" -eq "$cursor_pos" ]; then
          echo -e " ${CYAN}${BOLD}→${NC} [ ] ${BOLD}$pkg${NC} - $desc"
        else
          echo -e "   [ ] ${BOLD}$pkg${NC} - $desc"
        fi
      fi
    done
    
    echo -e "\n${GRAY}Use ↑/↓ arrows to navigate, SPACE to toggle selection, ENTER to confirm${NC}"
  }
  
  # Process keypress function
  process_key() {
    local key
    
    # Read a single character
    key=$(dd bs=1 count=1 2>/dev/null)
    
    # Handle escape sequences (arrow keys)
    if [[ $key = $ESC ]]; then
      read -t 0.1 -rsn1 key
      if [[ $key = "[" ]]; then
        read -t 0.1 -rsn1 key
        case $key in
          A) # Up arrow
            ((cursor_pos--))
            if [ $cursor_pos -lt 0 ]; then
              cursor_pos=$((menu_size - 1))
            fi
            ;;
          B) # Down arrow
            ((cursor_pos++))
            if [ $cursor_pos -ge $menu_size ]; then
              cursor_pos=0
            fi
            ;;
        esac
      fi
    elif [[ $key = " " ]]; then # Spacebar
      # Toggle selection state
      if [[ " ${selected[*]} " =~ " $cursor_pos " ]]; then
        # Remove from selected array
        local temp_selected=()
        for i in "${selected[@]}"; do
          if [ "$i" != "$cursor_pos" ]; then
            temp_selected+=($i)
          fi
        done
        selected=("${temp_selected[@]}")
      else
        # Add to selected array
        selected+=($cursor_pos)
      fi
    elif [[ $key = $'\r' ]]; then # Enter key
      return 1
    fi
    return 0
  }
  
  # Main menu loop
  while true; do
    render_menu
    process_key || break
  done
  
  # Restore terminal settings (with error suppression)
  stty echo -raw 2>/dev/null
  tput cnorm >/dev/null 2>&1
  echo
}

# Fallback menu for terminals without advanced capabilities
basic_interactive_menu() {
  local -n items=$1        # Reference to array of items to display
  local -n selected=$2     # Reference to array to store selected indexes
  local title=$3           # Title to display
  local default_state=$4   # Default selection state (true/false)
  
  echo -e "${BOLD}${title}${NC}"
  echo "Select items by typing their numbers separated by spaces."
  echo -e "Default selections are marked with [${GREEN}x${NC}].\n"
  
  # Show the list with numbers
  for i in "${!items[@]}"; do
    IFS=':' read -r pkg desc <<< "${items[$i]}"
    # Display default selection state
    if [[ " ${selected[*]} " =~ " $i " ]]; then
      echo -e "$((i+1)). [${GREEN}x${NC}] ${BOLD}$pkg${NC} - $desc"
    else
      echo -e "$((i+1)). [ ] ${BOLD}$pkg${NC} - $desc"
    fi
  done
  
  # Get user input
  echo
  echo -e "${GRAY}Enter numbers to select (press ENTER to accept defaults):${NC}"
  read -r user_selection
  
  # Process user input if any was provided
  if [ -n "$user_selection" ]; then
    # Clear the selected array since we're setting a new custom selection
    selected=()
    
    # Parse each number
    for num in $user_selection; do
      # Convert to 0-based index and add to selected array
      idx=$((num-1))
      # Verify it's a valid index
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#items[@]}" ]; then
        selected+=($idx)
      fi
    done
  fi
  
  # Show final selection
  echo -e "\n${BOLD}Selected items:${NC}"
  for i in "${selected[@]}"; do
    IFS=':' read -r pkg desc <<< "${items[$i]}"
    echo -e "  ${GREEN}✓${NC} $pkg - $desc"
  done
  echo
}

# Function to display package selection
select_packages() {
  # Clear the global array
  SELECTED_PACKAGES=()
  
  echo -e "\n${BOLD}${CYAN}Select packages to install:${NC}"
  
  if [ "$INTERACTIVE" = true ]; then
    # Arrays to store selected indexes
    local essential_selected=()
    local recommended_selected=()
    local advanced_selected=()
    
    # Run interactive selection for each category
    interactive_menu ESSENTIAL_TOOLS essential_selected "${BOLD}Essential Tools:${NC}" true
    interactive_menu RECOMMENDED_TOOLS recommended_selected "${BOLD}Recommended Tools:${NC}" true
    interactive_menu ADVANCED_TOOLS advanced_selected "${BOLD}Advanced Tools:${NC}" false
    
    # Add selected tools to global SELECTED_PACKAGES array
    for i in "${essential_selected[@]}"; do
      SELECTED_PACKAGES+=("${ESSENTIAL_TOOLS[$i]}")
    done
    
    for i in "${recommended_selected[@]}"; do
      SELECTED_PACKAGES+=("${RECOMMENDED_TOOLS[$i]}")
    done
    
    for i in "${advanced_selected[@]}"; do
      SELECTED_PACKAGES+=("${ADVANCED_TOOLS[$i]}")
    done
  else
    # Non-interactive mode uses default selections
    if [ "$INSTALL_ESSENTIALS" = true ]; then
      for tool in "${ESSENTIAL_TOOLS[@]}"; do
        SELECTED_PACKAGES+=("$tool")
      done
    fi
    
    if [ "$INSTALL_RECOMMENDED" = true ]; then
      for tool in "${RECOMMENDED_TOOLS[@]}"; do
        SELECTED_PACKAGES+=("$tool")
      done
    fi
    
    if [ "$INSTALL_ADVANCED" = true ]; then
      for tool in "${ADVANCED_TOOLS[@]}"; do
        SELECTED_PACKAGES+=("$tool")
      done
    fi
  fi
  
  echo
  
  # Install selected packages
  for tool in "${SELECTED_PACKAGES[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    install_package "$pkg" "$desc"
  done
}

# Function to handle special package cases
handle_special_packages() {
  # Special case for exa which might need to be installed differently
  if ! command -v exa &>/dev/null && [ -n "$(echo "${SELECTED_PACKAGES[@]}" | grep -o "exa")" ]; then
    log "INFO" "Installing exa (modern ls replacement)..."
    
    case $OS_TYPE in
      debian)
        if ! command -v cargo &>/dev/null; then
          # Try to install from package if available
          sudo apt install -y exa || {
            # If not available, install rustup and use cargo
            log "INFO" "Installing rust to build exa..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source $HOME/.cargo/env
            cargo install exa
          }
        else
          cargo install exa
        fi
        ;;
      redhat)
        # Try specific package name or use cargo
        sudo $PKG_MANAGER install -y exa || {
          if ! command -v cargo &>/dev/null; then
            log "INFO" "Installing rust to build exa..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source $HOME/.cargo/env
          fi
          cargo install exa
        }
        ;;
      *)
        log "WARNING" "Skipping exa installation for this OS type."
        ;;
    esac
  fi
  # Special case for bat which might be named differently
  if ! command -v bat &>/dev/null && [ -n "$(echo "${SELECTED_PACKAGES[@]}" | grep -o "bat")" ]; then
    log "INFO" "Checking for bat alternatives..."
    
    case $OS_TYPE in
      debian)
        # On Debian/Ubuntu, bat might be installed as batcat
        if command -v batcat &>/dev/null; then
          log "INFO" "bat is installed as batcat, creating alias..."
          echo "alias bat='batcat'" >> $HOME/.bash_aliases
        else
          sudo apt install -y bat || sudo apt install -y batcat
        fi
        ;;
      *)
        log "INFO" "Trying standard installation for bat..."
        ;;
    esac
  fi
  
  # Special case for pfetch - install from GitHub
  if ! command -v pfetch &>/dev/null && [ -n "$(echo "${SELECTED_PACKAGES[@]}" | grep -o "pfetch")" ]; then
    log "INFO" "Installing pfetch from GitHub..."
    
    # Create a temporary directory
    local temp_dir="/tmp/pfetch_install"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download pfetch from GitHub
    log "INFO" "Downloading pfetch..."
    if wget https://github.com/dylanaraps/pfetch/archive/master.zip; then
      # Extract the zip file
      log "INFO" "Extracting pfetch..."
      unzip master.zip
      
      # Install pfetch
      log "INFO" "Installing pfetch to /usr/local/bin/..."
      sudo install pfetch-master/pfetch /usr/local/bin/
      
      # Clean up
      cd - > /dev/null
      rm -rf "$temp_dir"
      
      if command -v pfetch &>/dev/null; then
        log "SUCCESS" "pfetch installed successfully."
      else
        log "ERROR" "Failed to install pfetch."
      fi
    else
      log "ERROR" "Failed to download pfetch from GitHub."
      cd - > /dev/null
      rm -rf "$temp_dir"
    fi
  fi
}

# Function to install JetBrainsMono Nerd Font
install_nerd_font() {
  if [ "$INSTALL_NERD_FONT" = false ]; then
    return 0
  fi
  
  log "INFO" "Installing JetBrainsMono Nerd Font..."
  
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  
  # Download JetBrainsMono Nerd Font
  log "INFO" "Downloading JetBrainsMono Nerd Font..."
  
  # The GitHub raw URL structure has changed, using a more reliable approach
  local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  local temp_zip="/tmp/JetBrainsMono.zip"
  
  # Download the zip file
  if curl -fLo "$temp_zip" "$font_url"; then
    log "INFO" "Font downloaded successfully, extracting..."
    
    # Create a temporary directory for extraction
    local temp_dir="/tmp/jetbrains_font"
    mkdir -p "$temp_dir"
    
    # Extract the zip file
    unzip -q "$temp_zip" -d "$temp_dir"
    
    # Copy the Medium variant to the fonts directory
    cp "$temp_dir/JetBrains Mono Medium Nerd Font Complete Mono.ttf" "$font_dir/" 2>/dev/null || \
    cp "$temp_dir/JetBrainsMono Medium Nerd Font Complete Mono.ttf" "$font_dir/" 2>/dev/null || \
    cp "$temp_dir"/*Medium*Mono.ttf "$font_dir/" 2>/dev/null || \
    cp "$temp_dir"/*.ttf "$font_dir/" 2>/dev/null
    
    # Clean up
    rm -rf "$temp_dir" "$temp_zip"
    log "INFO" "Font files extracted to $font_dir"
  else
    log "WARNING" "Failed to download font. Continuing without Nerd Font installation."
  fi
  
  # Update font cache
  if command -v fc-cache &>/dev/null; then
    fc-cache -f -v
    log "SUCCESS" "Font cache updated."
  else
    log "WARNING" "fc-cache not available, font cache not updated."
  fi
  
  log "SUCCESS" "JetBrainsMono Nerd Font installed."
}

# Function to configure custom prompt
configure_prompt() {
  if [ "$CONFIGURE_PROMPT" = false ]; then
    return 0
  fi
  
  log "INFO" "Configuring custom shell prompt..."
  
  # Detect shell
  local shell_config=""
  if [ -n "$BASH_VERSION" ]; then
    shell_config="$HOME/.bashrc"
  elif [ -n "$ZSH_VERSION" ]; then
    shell_config="$HOME/.zshrc"
  else
    # Default to bashrc if we can't detect
    shell_config="$HOME/.bashrc"
  fi
  
  # Create a backup
  cp "$shell_config" "${shell_config}.bak.$(date +%Y%m%d%H%M%S)"
  
  # Add custom prompt configuration
  cat >> "$shell_config" << 'EOF'

# Custom prompt configuration by ServerCozy
prompt_command() {
  local EXIT="$?"
  local BLUE="\[\033[38;5;39m\]"
  local GREEN="\[\033[38;5;76m\]"
  local RED="\[\033[38;5;196m\]"
  local YELLOW="\[\033[38;5;220m\]"
  local CYAN="\[\033[38;5;44m\]"
  local RESET="\[\033[0m\]"
  local BOLD="\[\033[1m\]"
  
  # Get current git branch if applicable
  local git_branch=""
  if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
    git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --always 2>/dev/null)
    git_branch=" (${YELLOW}${git_branch}${RESET})"
  fi
  
  # Shorten path if it's too long
  local pwd_length=30
  local pwd_symbol="…"
  local pwd_path="$PWD"
  
  # Replace $HOME with ~
  pwd_path="${pwd_path/#$HOME/~}"
  
  if [ $(echo -n "$pwd_path" | wc -c) -gt $pwd_length ]; then
    local pwd_offset=$(( $(echo -n "$pwd_path" | wc -c) - $pwd_length ))
    pwd_path="${pwd_symbol}${pwd_path:$pwd_offset:$pwd_length}"
  fi
  
  # Set the prompt symbol and color based on exit status
  local symbol=""
  if [ $EXIT -eq 0 ]; then
    symbol="${GREEN}❱${RESET}"
  else
    symbol="${RED}❱${RESET}"
  fi
  
  # Set the actual prompt
  PS1="${BOLD}\u${RESET}@${BOLD}\h${RESET} ${CYAN}${pwd_path}${RESET}${git_branch} ${symbol} "
}

# Set the prompt command
PROMPT_COMMAND=prompt_command

EOF
  
  log "SUCCESS" "Custom prompt configured."
}

# Function to configure useful aliases
configure_aliases() {
  if [ "$CONFIGURE_ALIASES" = false ]; then
    return 0
  fi
  
  log "INFO" "Configuring useful aliases..."
  
  # Detect shell
  local aliases_file="$HOME/.bash_aliases"
  if [ -n "$ZSH_VERSION" ]; then
    aliases_file="$HOME/.zsh_aliases"
    
    # Make sure the aliases file is sourced in .zshrc
    if ! grep -q "source.*$aliases_file" "$HOME/.zshrc"; then
      echo "[ -f $aliases_file ] && source $aliases_file" >> "$HOME/.zshrc"
    fi
  elif [ -n "$BASH_VERSION" ]; then
    # Make sure the aliases file is sourced in .bashrc
    if ! grep -q "source.*$aliases_file" "$HOME/.bashrc"; then
      echo "[ -f $aliases_file ] && source $aliases_file" >> "$HOME/.bashrc"
    fi
  fi
  
  # Create aliases file if it doesn't exist
  touch "$aliases_file"
  
  # Add useful aliases
  cat >> "$aliases_file" << 'EOF'
# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# List directory contents
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Enhanced commands (if installed)
if command -v exa &>/dev/null; then
  alias ls='exa --icons'
  alias ll='exa -alF --icons'
  alias lt='exa -T --icons'
fi

if command -v batcat &>/dev/null; then
  alias bat='batcat'
fi

if command -v bat &>/dev/null; then
  alias cat='bat --style=plain'
fi

# System information
if command -v pfetch &>/dev/null; then
  alias sysinfo='pfetch'
else
  alias sysinfo='echo -e "\n$(hostname) $(date)" && cat /etc/*release && echo -e "\nKernel: $(uname -r)" && echo -e "Memory: $(free -h | grep Mem | awk "{print \$3\"/\"\$2}")" && echo -e "Disk: $(df -h / | grep / | awk "{print \$3\"/\"\$2}")"'
fi

# Git repositories status
alias repofetch='find . -maxdepth 3 -type d -name ".git" | while read dir; do cd $(dirname $dir) && echo -e "\033[1;36m$(basename $(pwd))\033[0m: $(git branch --show-current) [$(git config --get remote.origin.url 2>/dev/null || echo "No remote")]" && cd - > /dev/null; done'

# Common shortcuts
alias h='history'
alias j='jobs -l'
alias p='ps -ef'
alias vi='vim'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias path='echo -e ${PATH//:/\\n}'

# Server specific
alias ports='netstat -tulanp'
alias meminfo='free -m -l -t'
alias cpuinfo='lscpu'
alias disk='df -h'
alias dirsize='du -sh'
alias running='ps aux | grep'

# Help command for ServerCozy tools
alias help='echo -e "Custom commands:\n  sysinfo - Show system information\n  repofetch - Check git repositories status\n  ports - Show open ports\n  meminfo - Show memory information\n  cpuinfo - Show CPU information\n  disk - Show disk usage\n  dirsize - Show directory size\n  running - Search for running processes"'
EOF
  
  log "SUCCESS" "Useful aliases configured in $aliases_file."
}

# Function to configure vim
configure_vim() {
  if [ "$CONFIGURE_VIM" = false ]; then
    return 0
  fi
  
  log "INFO" "Configuring vim..."
  
  # Create .vimrc file
  cat > "$HOME/.vimrc" << 'EOF'
" Basic settings
syntax on
set number
set ruler
set showcmd
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set tabstop=2
set shiftwidth=2
set expandtab
set smarttab
set autoindent
set smartindent
set backspace=indent,eol,start
set cursorline
set wildmenu
set wildmode=list:longest,full
set laststatus=2
set title
set history=1000
set mouse=a
set ttymouse=sgr

" Colors
set t_Co=256
set background=dark
highlight LineNr term=bold cterm=NONE ctermfg=DarkGrey ctermbg=NONE

" Statusline
set statusline=%F%m%r%h%w\ [FORMAT=%{&ff}]\ [TYPE=%Y]\ [POS=%l,%v][%p%%]\ [BUFFER=%n]

" Filetype detection
filetype on
filetype plugin on
filetype indent on

" Key mappings
nnoremap <C-j> :bnext<CR>
nnoremap <C-k> :bprev<CR>
nnoremap <C-h> :tabprevious<CR>
nnoremap <C-l> :tabnext<CR>
nnoremap <C-t> :tabnew<CR>
nnoremap <C-s> :w<CR>
EOF
  
  log "SUCCESS" "Vim configured."
}

# Function to show summary of installed tools
show_summary() {
  echo -e "\n${BOLD}${GREEN}=== ServerCozy Setup Complete ===${NC}"
  echo -e "${BOLD}The following improvements have been made:${NC}"
  
  # Check installed packages
  echo -e "\n${BOLD}Installed Tools:${NC}"
  
  local all_tools=("${ESSENTIAL_TOOLS[@]}" "${RECOMMENDED_TOOLS[@]}" "${ADVANCED_TOOLS[@]}")
  local installed_count=0
  
  for tool in "${all_tools[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    if command -v "$pkg" &>/dev/null || is_installed "$pkg"; then
      echo -e "  ${GREEN}✓${NC} $pkg - $desc"
      installed_count=$((installed_count+1))
    fi
  done
  
  if [ $installed_count -eq 0 ]; then
    echo -e "  ${YELLOW}No tools were installed.${NC}"
  fi
  
  # Check shell customizations
  echo -e "\n${BOLD}Shell Customizations:${NC}"
  if [ "$CONFIGURE_PROMPT" = true ]; then
    echo -e "  ${GREEN}✓${NC} Custom prompt installed"
  fi
  if [ "$CONFIGURE_ALIASES" = true ]; then
    echo -e "  ${GREEN}✓${NC} Useful aliases configured"
  fi
  if [ "$CONFIGURE_VIM" = true ]; then
    echo -e "  ${GREEN}✓${NC} Vim configured"
  fi
  if [ "$INSTALL_NERD_FONT" = true ]; then
    echo -e "  ${GREEN}✓${NC} JetBrainsMono Nerd Font installed"
  fi
  
  echo -e "\n${BOLD}${CYAN}To apply all changes, either:${NC}"
  echo -e "  ${YELLOW}1. Log out and log back in${NC}"
  echo -e "  ${YELLOW}2. Run: source ~/.bashrc (or ~/.zshrc if using zsh)${NC}"
  
  echo -e "\n${BOLD}${CYAN}For more information, type:${NC} ${YELLOW}help${NC}"
  echo -e "${GRAY}Log file saved to: $LOG_FILE${NC}"
}

# Function to check sudo access
check_sudo() {
  log "INFO" "Checking sudo access..."
  
  if ! command -v sudo &>/dev/null; then
    log "ERROR" "sudo command not found. Please install sudo package."
    exit 1
  fi
  
  # Test sudo access
  if ! sudo -n true 2>/dev/null; then
    log "WARNING" "You may be asked for your password to run commands with sudo."
    if ! sudo true; then
      log "ERROR" "Failed to get sudo access. Exiting."
      exit 1
    fi
  fi
  
  log "SUCCESS" "Sudo access confirmed."
}

# Main function
main() {
  # Display banner
  echo -e "${BLUE}${BOLD}===========================================================${NC}"
  echo -e "${BLUE}${BOLD}           ServerCozy v${VERSION}            ${NC}"
  echo -e "${BLUE}${BOLD}===========================================================${NC}"
  echo
  
  # Set up logging
  echo "=== ServerCozy Log $(date) ===" > "$LOG_FILE"
  
  # Check sudo access
  check_sudo
  
  # Detect operating system
  detect_os
  
  # Update package repositories
  update_package_repos
  
  # Select and install packages
  select_packages
  
  # Handle special package cases
  handle_special_packages
  
  # Install Nerd Font
  install_nerd_font
  
  # Configure shell prompt
  configure_prompt
  
  # Configure aliases
  configure_aliases
  
  # Configure vim
  configure_vim
  
  # Show summary
  show_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive)
      INTERACTIVE=false
      shift
      ;;
    --essential-only)
      INSTALL_ESSENTIALS=true
      INSTALL_RECOMMENDED=false
      INSTALL_ADVANCED=false
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      show_help
      exit 1
      ;;
  esac
done

# Run main function
main
