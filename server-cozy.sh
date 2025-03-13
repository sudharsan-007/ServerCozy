 #!/usr/bin/env bash
#
# server-cozy.sh - ServerCozy
#
# This script enhances a cloud server environment with useful tools and configurations.
# It automates the installation of common utilities, shell improvements, and productivity tools.
#
# Author: Sudharsan Ananth
# Version: 1.9.3
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

# Enhanced error handling
set -o pipefail # Exit if any command in a pipeline fails
set -u          # Treat unset variables as errors
set -E          # Ensure ERR trap is inherited by shell functions

# Check for bash as this script uses bash-specific features
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Error: This script requires bash to run."
  echo "Please run this script with bash: bash $(basename "$0")"
  exit 1
fi

# Global variables for cleanup and state tracking
temp_zip=""
temp_dir=""
installation_step=""
restored_files=()
backup_files=()

# Cleanup function to remove temporary files on exit
cleanup() {
  # Remove any temporary files
  [ -n "$temp_zip" ] && [ -f "$temp_zip" ] && rm -f "$temp_zip"
  [ -n "$temp_dir" ] && [ -d "$temp_dir" ] && rm -rf "$temp_dir"
  
  # Log the cleanup
  echo "Cleanup complete" >> "$LOG_FILE"
}

# Error handler function for controlled failures
error_handler() {
  local err=$?
  local line=$1
  local command="${BASH_COMMAND}"
  
  # Only execute if this is a real error, not just a trapped exit
  if [ $err -ne 0 ]; then
    echo -e "\n${RED}${BOLD}Error occurred:${NC} at line $line"
    echo -e "Command: $command"
    echo -e "Exit code: $err"
    echo -e "\n${YELLOW}Current step: $installation_step${NC}"
    
    # Log the error
    if [ -n "$LOG_FILE" ]; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] Error $err occurred at line $line: $command" >> "$LOG_FILE"
    fi
    
    # If we've created backups, offer to restore
    if [ ${#backup_files[@]} -gt 0 ] && [ "$INTERACTIVE" = true ]; then
      echo -e "\n${YELLOW}Would you like to attempt to restore backup files? (y/n)${NC}"
      read -p "> " restore_choice
      
      if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}Restoring backup files...${NC}"
        for backup in "${backup_files[@]}"; do
          original="${backup%.bak.*}"
          if [ -f "$backup" ]; then
            cp "$backup" "$original" && echo "Restored: $original" && restored_files+=("$original")
          fi
        done
        echo -e "\n${GREEN}Restore complete for ${#restored_files[@]} files.${NC}"
      fi
    fi
  fi
  
  # Always perform cleanup
  cleanup
}

# Trap error handler on ERR signal (bash-specific feature)
trap 'error_handler ${LINENO}' ERR

# Signal handler for graceful termination on user interruptions
handle_signal() {
  log "WARNING" "Received termination signal. Cleaning up and exiting..."
  echo -e "\n${RED}${BOLD}Script interrupted at step: $installation_step${NC}"
  echo -e "${RED}${BOLD}Cleaning up...${NC}"
  cleanup
  exit 1
}

# Trap interruption signals
trap handle_signal INT TERM

# Check if script is executable
check_executable() {
  if [ ! -x "$0" ]; then
    echo "Warning: Script is not executable. Running anyway, but for future use:"
    echo "Run: chmod +x $0"
  fi
}

# Script version
VERSION="1.9.3"
SCRIPT_VERSION="$VERSION"

# Default values
INTERACTIVE=true
INSTALL_ESSENTIALS=true
INSTALL_RECOMMENDED=true
INSTALL_ADVANCED=false
INSTALL_NERD_FONT=true
CONFIGURE_PROMPT=true
CONFIGURE_ALIASES=true
CONFIGURE_VIM=true
USE_DIALOG=true  # By default, use dialog TUI if available
DIALOG_AVAILABLE=false  # Will be set to true if dialog is available/installed
LOG_FILE="/tmp/servercozy-$(date +%Y%m%d%H%M%S).log"
LOG_DEBUG=false  # Debug logging flag - set to true to enable verbose debug logs
USER_INSTALL_ONLY=false # Default to system-wide installation
SUDO_CMD="" # Command to use for privileged operations (sudo, doas, or empty for root)
SUDO_AVAILABLE=false # Whether sudo is available
DOAS_AVAILABLE=false # Whether doas is available (for BSD systems)
SKIP_UPDATE_CHECK=false # Whether to skip checking for script updates
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
  "eza:Modern replacement for ls (successor to exa)"
  "bat:Cat clone with syntax highlighting"
  "ncdu:Disk usage analyzer with ncurses interface"
  "tldr:Simplified man pages"
  "jq:Lightweight and flexible command-line JSON processor"
  "fzf:Command-line fuzzy finder"
  "pfetch:Simple system information tool"
)

ADVANCED_TOOLS=(
  "ripgrep:Line-oriented search tool (rg)"
  "fd-find:Simple, fast, and user-friendly alternative to find (fd)"
  "neofetch:Command-line system information tool"
  "micro:Modern and intuitive terminal-based text editor"
  "zoxide:Smarter cd command (z)"
  "btop:Resource monitor that shows usage and stats for CPU, memory, network and storage"
)

# Function to display help
show_help() {
  echo -e "${BLUE}${BOLD}ServerCozy v${SCRIPT_VERSION}${NC}"
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
  echo "  --no-dialog          Force text-based interface (don't use dialog TUI)"
  echo "  --user-only          Skip system-wide installations, use user directory only"
  echo "  --no-nerd-font       Skip Nerd Font installation"
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

# Improved command existence checking with multiple methods
command_exists() {
  local cmd="$1"
  
  # Try multiple methods to check for command existence
  if command -v "$cmd" &>/dev/null; then
    return 0
  elif type "$cmd" &>/dev/null; then
    return 0
  elif which "$cmd" &>/dev/null; then
    return 0
  elif hash "$cmd" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Function to create and check a lock file to prevent multiple script instances
check_lock() {
  local lock_file="/tmp/servercozy.lock"
  
  # Check if lock file exists and process still running
  if [ -f "$lock_file" ]; then
    local pid=$(cat "$lock_file" 2>/dev/null)
    
    # Check if pid is a number and process exists
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      log "ERROR" "Another instance of ServerCozy is already running (PID: $pid)"
      echo -e "${RED}${BOLD}Error:${NC} Another instance of ServerCozy is already running."
      echo "If you're sure no other instance is running, delete the lock file:"
      echo "rm $lock_file"
      exit 1
    else
      log "WARNING" "Stale lock file found, removing"
    fi
  fi
  
  # Create lock file with current PID
  echo $$ > "$lock_file"
  
  # Remove lock file on exit
  trap "rm -f '$lock_file'; exit" EXIT HUP INT TERM
}

# Create temporary directory with proper error handling and cleanup
create_temp_dir() {
  local prefix="${1:-servercozy}"
  local temp_dir
  
  temp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXX" 2>/dev/null) || {
    log "ERROR" "Failed to create temporary directory"
    echo -e "${RED}${BOLD}Error:${NC} Failed to create temporary directory"
    exit 1
  }
  
  echo "$temp_dir"
}

# Function to detect operating system with extended support
detect_os() {
  log "INFO" "Detecting operating system..."
  
  # macOS detection
  if [ "$(uname)" = "Darwin" ]; then
    OS_TYPE="macos"
    if command_exists brew; then
      PKG_MANAGER="brew"
      OS_NAME="macOS (Homebrew)"
      OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    else
      log "WARNING" "Homebrew not found. Some features may not work properly."
      PKG_MANAGER="none"
      OS_NAME="macOS"
      OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    fi
    log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    return
  fi
  
  # WSL detection
  if [ -f /proc/version ] && grep -q "Microsoft" /proc/version; then
    IS_WSL=true
    log "INFO" "Detected Windows Subsystem for Linux"
  else
    IS_WSL=false
  fi
  
  # BSD variants
  if [ "$(uname)" = "FreeBSD" ] || [ "$(uname)" = "OpenBSD" ] || [ "$(uname)" = "NetBSD" ]; then
    OS_TYPE="bsd"
    OS_NAME="$(uname)"
    OS_VERSION="$(uname -r)"
    PKG_MANAGER="pkg"
    log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    return
  fi
  
  # Linux detection
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
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    elif [[ $OS_NAME == *"Alpine"* ]]; then
      OS_TYPE="alpine"
      PKG_MANAGER="apk"
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    elif [[ $OS_NAME == *"Arch"* ]] || [[ $OS_NAME == *"Manjaro"* ]]; then
      OS_TYPE="arch"
      PKG_MANAGER="pacman"
      log "INFO" "Detected ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
    else
      log "WARNING" "Unsupported distribution: ${OS_NAME}. Will try to detect package manager."
      OS_TYPE="unknown"
      
      # Try to detect package manager
      if command_exists apt; then
        PKG_MANAGER="apt"
      elif command_exists dnf; then
        PKG_MANAGER="dnf"
      elif command_exists yum; then
        PKG_MANAGER="yum"
      elif command_exists apk; then
        PKG_MANAGER="apk"
      elif command_exists pacman; then
        PKG_MANAGER="pacman"
      else
        log "WARNING" "Could not detect package manager. Some features may not work."
        PKG_MANAGER="unknown"
      fi
      
      log "INFO" "Using ${PKG_MANAGER} for package management."
    fi
  elif [ -f /etc/lsb-release ]; then
    # Alternative method for Ubuntu/Debian
    . /etc/lsb-release
    OS_NAME="$DISTRIB_ID"
    OS_VERSION="$DISTRIB_RELEASE"
    OS_TYPE="debian"
    PKG_MANAGER="apt"
    log "INFO" "Detected ${OS_NAME} ${OS_VERSION} using lsb-release (using ${PKG_MANAGER})"
  else
    # Very basic fallback detection
    if command_exists apt; then
      OS_TYPE="debian"
      PKG_MANAGER="apt"
    elif command_exists dnf; then
      OS_TYPE="redhat"
      PKG_MANAGER="dnf"
    elif command_exists yum; then
      OS_TYPE="redhat"
      PKG_MANAGER="yum"
    elif command_exists apk; then
      OS_TYPE="alpine"
      PKG_MANAGER="apk"
    elif command_exists pacman; then
      OS_TYPE="arch"
      PKG_MANAGER="pacman"
    else
      log "WARNING" "Could not detect operating system package manager! Some features may not work."
      OS_TYPE="unknown"
      PKG_MANAGER="unknown"
    fi
    OS_NAME="$(uname -s)"
    OS_VERSION="$(uname -r)"
    log "INFO" "Basic detection: ${OS_NAME} ${OS_VERSION} (using ${PKG_MANAGER})"
  fi
}

# Function to check network connectivity with fallbacks for different systems
check_connectivity() {
  log "INFO" "Checking internet connectivity..."
  
  # Try multiple domains to ensure reliable checking
  local check_domains=("google.com" "github.com" "cloudflare.com")
  local connected=false
  
  # First try: ping (may be restricted on some systems)
  for domain in "${check_domains[@]}"; do
    # Check for ping command and adjust flags based on OS
    if command_exists ping; then
      if [ "$(uname)" = "Darwin" ] || [ "$(uname)" = "FreeBSD" ]; then
        # macOS and FreeBSD syntax
        if ping -c 1 -t 2 "$domain" &>/dev/null; then
          connected=true
          break
        fi
      else
        # Linux syntax
        if ping -c 1 -W 2 "$domain" &>/dev/null; then
          connected=true
          break
        fi
      fi
    fi
  done
  
  # Second try: Use curl if ping failed or isn't available
  if [ "$connected" = false ] && command_exists curl; then
    for domain in "${check_domains[@]}"; do
      if curl --silent --head --max-time 2 "https://$domain" &>/dev/null; then
        connected=true
        break
      fi
    done
  fi
  
  # Third try: Use wget if curl failed or isn't available
  if [ "$connected" = false ] && command_exists wget; then
    for domain in "${check_domains[@]}"; do
      if wget --spider --quiet --timeout=2 "https://$domain" &>/dev/null; then
        connected=true
        break
      fi
    done
  fi
  
  # Fourth try: Use nc/netcat if available (common on Unix systems)
  if [ "$connected" = false ] && (command_exists nc || command_exists netcat); then
    local nc_cmd="nc"
    command_exists netcat && nc_cmd="netcat"
    
    for domain in "${check_domains[@]}"; do
      if $nc_cmd -z -w 2 "$domain" 443 &>/dev/null; then
        connected=true
        break
      fi
    done
  fi
  
  if [ "$connected" = false ]; then
    log "WARNING" "No internet connectivity detected. Some features may not work."
    return 1
  else
    log "SUCCESS" "Internet connectivity confirmed."
    return 0
  fi
}

# Function to update package repositories
update_package_repos() {
  log "INFO" "Updating package repositories..."
  
  # Check connectivity first
  check_connectivity || log "WARNING" "Proceeding with limited connectivity. Repository updates may fail."
  
  # Skip if user-only installation mode and not homebrew
  if [ "$USER_INSTALL_ONLY" = true ] && [ "$PKG_MANAGER" != "brew" ]; then
    log "WARNING" "Skipping system repository updates in user-only mode."
    return 0
  fi
  
  case $PKG_MANAGER in
    apt)
      run_with_privileges apt update -y || log "WARNING" "Failed to update apt repositories"
      ;;
    dnf|yum)
      run_with_privileges $PKG_MANAGER check-update -y || true  # check-update returns 100 when updates available
      ;;
    apk)
      run_with_privileges apk update || log "WARNING" "Failed to update apk repositories"
      ;;
    brew)
      brew update || log "WARNING" "Failed to update Homebrew"
      ;;
    pacman)
      run_with_privileges pacman -Sy || log "WARNING" "Failed to update pacman repositories"
      ;;
    pkg)
      run_with_privileges pkg update || log "WARNING" "Failed to update pkg repositories"
      ;;
    none|unknown)
      log "WARNING" "No suitable package manager found. Skipping repository update."
      ;;
    *)
      log "WARNING" "Unknown package manager ($PKG_MANAGER). Skipping repository update."
      ;;
  esac
  
  log "SUCCESS" "Package repositories updated."
}
# Function to safely backup a configuration file before modifying it
backup_config_file() {
  local file="$1"
  
  if [ -f "$file" ]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    log "INFO" "Creating backup of $file to $backup"
    cp "$file" "$backup"
    backup_files+=("$backup")
    return 0
  else
    log "INFO" "File $file doesn't exist, no backup needed"
    return 1
  fi
}

# Function to check if a package is installed
is_installed() {
  local package_name="$1"
  local result=1  # Default to not installed
  
  case $PKG_MANAGER in
    apt)
      dpkg -l | grep -q "ii  $package_name "
      result=$?
      ;;
    dnf|yum)
      rpm -q "$package_name" &>/dev/null
      result=$?
      ;;
    apk)
      apk info -e "$package_name" &>/dev/null
      result=$?
      ;;
    brew)
      brew list "$package_name" &>/dev/null
      result=$?
      ;;
    pacman)
      pacman -Q "$package_name" &>/dev/null
      result=$?
      ;;
    pkg)
      pkg info -e "$package_name" &>/dev/null
      result=$?
      ;;
    *)
      command -v "$package_name" &>/dev/null
      result=$?
      ;;
  esac
  
  # Log the result for debugging
  if [ $result -eq 0 ]; then
    log "INFO" "DEBUG: Package $package_name is already installed"
  else
    log "INFO" "DEBUG: Package $package_name is not installed (exit code $result)"
  fi
  
  return $result
}

# Function to detect system architecture and set appropriate variables
detect_arch() {
  log "INFO" "Detecting system architecture..."
  
  local arch=$(uname -m)
  ARCH="$arch"
  
  case "$arch" in
    x86_64|amd64)
      ARCH_TYPE="amd64"
      log "INFO" "Detected x86_64/amd64 architecture"
      ;;
    aarch64|arm64)
      ARCH_TYPE="arm64"
      log "INFO" "Detected ARM64 architecture"
      ;;
    armv7*|armhf)
      ARCH_TYPE="armhf"
      log "INFO" "Detected ARM (32-bit) architecture"
      ;;
    i386|i686)
      ARCH_TYPE="i386"
      log "INFO" "Detected i386/i686 architecture"
      ;;
    *)
      ARCH_TYPE="unknown"
      log "WARNING" "Unknown architecture: $arch. Some features may not work correctly."
      ;;
  esac
  
  return 0
}

# Create a flexible download function that uses available tools with retry
download_file() {
  local url="$1"
  local output_file="$2"
  local max_retries="${3:-3}"  # Default to 3 retries if not specified
  local retry_delay="${4:-5}"  # Default to 5 seconds between retries
  local success=false
  local attempt=1
  
  log "INFO" "Downloading $url to $output_file"
  
  while [ "$attempt" -le "$max_retries" ] && [ "$success" = false ]; do
    if [ "$attempt" -gt 1 ]; then
      log "INFO" "Retry attempt $attempt/$max_retries after $retry_delay seconds..."
      sleep "$retry_delay"
    fi
    
    # Try curl first
    if command_exists curl; then
      log "INFO" "Using curl..."
      if curl -fsSL --connect-timeout 15 --retry 3 "$url" -o "$output_file"; then
        success=true
        continue
      else
        log "WARNING" "curl download failed"
      fi
    fi
    
    # If curl failed or doesn't exist, try wget
    if [ "$success" = false ] && command_exists wget; then
      log "INFO" "Using wget..."
      if wget --timeout=15 --tries=3 -q "$url" -O "$output_file"; then
        success=true
        continue
      else
        log "WARNING" "wget download failed"
      fi
    fi
    
    # Increment attempt counter
    attempt=$((attempt+1))
  done
  
  # Return success/failure
  if [ "$success" = true ]; then
    log "SUCCESS" "File downloaded successfully"
    return 0
  else
    log "ERROR" "Failed to download file after $max_retries attempts"
    return 1
  fi
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
  
  # Log more detailed debugging information
  log "INFO" "DEBUG: Starting installation process for $package_name"
  
  log "INFO" "Installing $package_name ($description)..."
  
  # Add diagnostic logging
  log "INFO" "DEBUG: is_installed result for $package_name: $?"
  
  # Try user-level installation in user-only mode for certain packages
  if [ "$USER_INSTALL_ONLY" = true ] && [ "$PKG_MANAGER" != "brew" ]; then
    log "INFO" "Attempting user-level installation for $package_name..."
    
    # Check if we can do a local install with npm, pip, or cargo
    if [[ "$package_name" == "tldr" ]] && command_exists npm; then
      npm install -g tldr || log "ERROR" "Failed to install $package_name with npm"
    elif [[ "$package_name" == "bat" || "$package_name" == "fd-find" || "$package_name" == "ripgrep" || "$package_name" == "eza" ]] && command_exists cargo; then
      cargo install "$package_name" || log "ERROR" "Failed to install $package_name with cargo"
    elif command_exists pip || command_exists pip3; then
      local pip_cmd="pip"
      command_exists pip3 && pip_cmd="pip3"
      $pip_cmd install --user "$package_name" || log "ERROR" "Failed to install $package_name with pip"
    else
      log "WARNING" "No suitable user-level installation method found for $package_name."
      return 1
    fi
    
    # Check if we succeeded
    if command_exists "$package_name"; then
      log "SUCCESS" "$package_name installed successfully via user-level installation."
      return 0
    else
      log "WARNING" "User-level installation of $package_name failed. Skipping."
      return 1
    fi
  fi
  
  # Proceed with system-level installation
  local install_output=""
  local install_exit_code=0
  local already_newest=false
  
  case $PKG_MANAGER in
    apt)
      # Capture output to check for "already newest version" message
      install_output=$(run_with_privileges apt install -y "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "is already the newest version"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with apt"
      fi
      ;;
    dnf|yum)
      install_output=$(run_with_privileges $PKG_MANAGER install -y "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "already installed"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with $PKG_MANAGER"
      fi
      ;;
    apk)
      install_output=$(run_with_privileges apk add "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "already exists"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with apk"
      fi
      ;;
    brew)
      install_output=$(brew install "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "already installed"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with Homebrew"
      fi
      ;;
    pacman)
      install_output=$(run_with_privileges pacman -S --noconfirm "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "is up to date"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with pacman"
      fi
      ;;
    pkg)
      install_output=$(run_with_privileges pkg install -y "$package_name" 2>&1) || install_exit_code=$?
      if echo "$install_output" | grep -q "already installed"; then
        already_newest=true
        log "SUCCESS" "$package_name is already the newest version."
      elif [ $install_exit_code -ne 0 ]; then
        log "ERROR" "Failed to install $package_name with pkg"
      fi
      ;;
    none|unknown)
      log "WARNING" "No package manager available. Skipping installation of $package_name."
      return 1
      ;;
    *)
      log "WARNING" "Unknown package manager: $PKG_MANAGER. Trying direct command lookup."
      # Just check if the command becomes available somehow (e.g., manual install)
      if command_exists "$package_name"; then
        log "SUCCESS" "$package_name is already available as a command."
        return 0
      else
        log "ERROR" "Unable to install $package_name with unknown package manager."
        return 1
      fi
      ;;
  esac
  
  # If the package is already the newest version, consider it a success
  if [ "$already_newest" = true ]; then
    return 0
  elif is_installed "$package_name"; then
    log "SUCCESS" "$package_name installed successfully."
    return 0
  else
    log "ERROR" "Failed to install $package_name."
    return 1
  fi
}

# Function to create a dialog-based checklist menu
dialog_menu() {
  local items_array_name=$1     # Name of the array containing items
  local selected_array_name=$2  # Name of the array to store selected indices
  local title=$3                # Title to display
  local default_state=$4        # Default selection state (true/false)
  
  # Get the array content through indirect reference
  eval "local items=(\"\${$items_array_name[@]}\")"
  
  # Temporary file to store dialog output
  local temp_file=$(mktemp)
  
  # Prepare dialog options
  local dialog_options=()
  local tag status item

  # Get terminal size for better dialog sizing
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  
  # Calculate dialog height and width (75% of terminal)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  # Calculate list height (dialog height minus overhead)
  local list_height=$((dialog_height - 8))
  
  # Build dialog options
  for i in "${!items[@]}"; do
    IFS=':' read -r item desc <<< "${items[$i]}"
    if [ "$default_state" = true ]; then
      status="ON"
    else
      status="OFF"
    fi
    dialog_options+=("$item" "$desc" "$status")
  done
  
  # Run the dialog checklist
  dialog --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "$title" \
         --checklist "Use UP/DOWN arrows to navigate, SPACE to toggle selection, ENTER to confirm" \
         $dialog_height $dialog_width $list_height \
         "${dialog_options[@]}" 2> "$temp_file"
  
  # Check if user cancelled with ESC or Cancel button
  if [ $? -ne 0 ]; then
    # If user cancelled, use all options if default_state is true, or none if false
    if [ "$default_state" = true ]; then
      # Select all items
      eval "$selected_array_name=()"
      for i in "${!items[@]}"; do
        eval "$selected_array_name+=($i)"
      done
    else
      # Select no items
      eval "$selected_array_name=()"
    fi
    rm -f "$temp_file"
    return
  fi
  
  # Process dialog output - convert to array indices
  eval "$selected_array_name=()"
  
  # Read selections from temp file
  local selections=$(cat "$temp_file")
  
  # Clean up temp file
  rm -f "$temp_file"
  
  # Process each selected item
  for selected in $selections; do
    # Remove quotes if present
    selected=${selected//\"/}
    
    # Find the index of this item in the original array
    for i in "${!items[@]}"; do
      IFS=':' read -r item desc <<< "${items[$i]}"
      if [ "$item" = "$selected" ]; then
        eval "$selected_array_name+=($i)"
        break
      fi
    done
  done
}

# Function to create a simple text-based checkbox menu
text_menu() {
  local items_array_name=$1     # Name of the array containing items
  local selected_array_name=$2  # Name of the array to store selected indices
  local title=$3                # Title to display
  local default_state=$4        # Default selection state (true/false)
  
  # Get the array content through indirect reference
  eval "local items=(\"\${$items_array_name[@]}\")"
  
  # Create an array to track selections (0=unselected, 1=selected)
  local selection_state=()
  
  # Initialize the selection state based on default state
  if [ "$default_state" = true ]; then
    for i in "${!items[@]}"; do
      selection_state[i]=1
    done
  else
    for i in "${!items[@]}"; do
      selection_state[i]=0
    done
  fi
  
  echo -e "\n${BOLD}${title}${NC}"
  
  # Display items with their selection state and numbers
  for i in "${!items[@]}"; do
    IFS=':' read -r pkg desc <<< "${items[$i]}"
    if [ "${selection_state[$i]}" -eq 1 ]; then
      echo -e "$((i+1)). [${GREEN}x${NC}] ${BOLD}$pkg${NC} - $desc"
    else
      echo -e "$((i+1)). [ ] ${BOLD}$pkg${NC} - $desc"
    fi
  done
  
  # Prompt user for selection
  echo -e "\n${GRAY}Enter numbers to toggle selection (e.g., \"1 3 5\")${NC}"
  echo -e "${GRAY}or press ENTER to accept current selection${NC}"
  echo -n "> "
  read -r selections
  
  # Process selections if user entered any
  if [ -n "$selections" ]; then
    for num in $selections; do
      # Convert to 0-based index
      idx=$((num-1))
      
      # Verify it's valid and toggle
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#items[@]}" ]; then
        if [ "${selection_state[$idx]}" -eq 1 ]; then
          selection_state[$idx]=0
        else
          selection_state[$idx]=1
        fi
      fi
    done
    
    # Show updated selection
    echo -e "\n${BOLD}Updated selection:${NC}"
    for i in "${!items[@]}"; do
      IFS=':' read -r pkg desc <<< "${items[$i]}"
      if [ "${selection_state[$i]}" -eq 1 ]; then
        echo -e "[${GREEN}x${NC}] ${BOLD}$pkg${NC}"
      fi
    done
  fi
  
  # Convert selection_state to selected indices and update the output array
  eval "$selected_array_name=()"
  for i in "${!selection_state[@]}"; do
    if [ "${selection_state[$i]}" -eq 1 ]; then
      eval "$selected_array_name+=($i)"
    fi
  done
}

# Function to choose between dialog and text menu based on availability
interactive_menu() {
  local items_array_name=$1     # Name of the array containing items
  local selected_array_name=$2  # Name of the array to store selected indices
  local title=$3                # Title to display
  local default_state=$4        # Default selection state (true/false)
  
  if [ "$DIALOG_AVAILABLE" = true ]; then
    dialog_menu "$items_array_name" "$selected_array_name" "$title" "$default_state"
  else
    text_menu "$items_array_name" "$selected_array_name" "$title" "$default_state"
  fi
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
    interactive_menu "ESSENTIAL_TOOLS" "essential_selected" "Essential Tools:" true
    interactive_menu "RECOMMENDED_TOOLS" "recommended_selected" "Recommended Tools:" true
    interactive_menu "ADVANCED_TOOLS" "advanced_selected" "Advanced Tools:" false
    
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
  
  # Show summary of selections
  echo -e "\n${BOLD}${CYAN}Summary of selections:${NC}"
  echo -e "The following tools will be installed:"
  
  local count=0
  for tool in "${SELECTED_PACKAGES[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    echo -e "  ${GREEN}•${NC} ${BOLD}$pkg${NC} - $desc"
    count=$((count+1))
  done
  
  if [ $count -eq 0 ]; then
    echo -e "  ${YELLOW}No tools selected${NC}"
  else
    echo -e "\n${CYAN}Installing $count tool(s)...${NC}"
  fi
  
  # Setup for progress display
  local total_packages=${#SELECTED_PACKAGES[@]}
  local current=0
  local progress_width=40
  
  # Display progress bar header
  echo -e "\n${BOLD}Installation Progress:${NC}"
  
  # Install selected packages with progress bar
  for tool in "${SELECTED_PACKAGES[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    
    # Update progress counter
    current=$((current + 1))
    
    # Calculate percentage and simplify the progress bar for better SSH compatibility
    local percent=$((current * 100 / total_packages))
    
    # Create a simpler ASCII progress bar that works better in SSH
    echo -ne "\r\033[K${BLUE}[$percent%]${NC} Installing: ${GREEN}$pkg${NC}"
    
    # Install the package
    if install_package "$pkg" "$desc"; then
      log "INFO" "DEBUG: install_package returned success for $pkg"
    else
      log "WARNING" "DEBUG: install_package returned error code $? for $pkg"
    fi
  done
  
  # Print newline after progress bar completes
  echo
}

# Function to handle special package cases
handle_special_packages() {
  # Special case for fd-find which might be named differently or need a symlink
  if [ -n "$(echo "${SELECTED_PACKAGES[@]}" | grep -o "fd-find")" ]; then
    log "INFO" "Handling fd-find installation and setup..."
    
    install_success=false
    local binary_name=""
    
    # Try to install with the appropriate package name for the distro
    case $OS_TYPE in
      debian)
        # On Debian/Ubuntu the package is fd-find but binary is fdfind
        if run_with_privileges apt install -y fd-find; then
          if command -v fdfind &>/dev/null; then
            binary_name="fdfind"
            install_success=true
            log "SUCCESS" "Installed fd-find package successfully."
          fi
        fi
        ;;
      redhat)
        # On Fedora it's fd-find, on newer versions might be just fd
        if run_with_privileges $PKG_MANAGER install -y fd-find 2>/dev/null; then
          if command -v fd-find &>/dev/null; then
            binary_name="fd-find"
            install_success=true
          elif command -v fdfind &>/dev/null; then
            binary_name="fdfind"
            install_success=true
          fi
          log "SUCCESS" "Installed fd-find package successfully."
        elif run_with_privileges $PKG_MANAGER install -y fd 2>/dev/null; then
          if command -v fd &>/dev/null; then
            binary_name="fd"
            install_success=true
            log "SUCCESS" "Installed fd package successfully."
          fi
        fi
        ;;
      alpine)
        # On Alpine it's simply fd
        if run_with_privileges apk add fd; then
          if command -v fd &>/dev/null; then
            binary_name="fd"
            install_success=true
            log "SUCCESS" "Installed fd package successfully."
          fi
        fi
        ;;
      *)
        # Try both names
        if run_with_privileges $PKG_MANAGER install -y fd-find 2>/dev/null || run_with_privileges $PKG_MANAGER install -y fd 2>/dev/null; then
          if command -v fd &>/dev/null; then
            binary_name="fd"
            install_success=true
          elif command -v fdfind &>/dev/null; then
            binary_name="fdfind"
            install_success=true
          elif command -v fd-find &>/dev/null; then
            binary_name="fd-find"
            install_success=true
          fi
          log "SUCCESS" "Installed fd package successfully."
        fi
        ;;
    esac
    
    # If installation failed, try with cargo
    if [ "$install_success" = false ] && command -v cargo &>/dev/null; then
      log "INFO" "Trying to install fd-find via cargo..."
      if cargo install fd-find; then
        log "SUCCESS" "Installed fd-find via cargo."
        install_success=true
        if command -v fd &>/dev/null; then
          binary_name="fd"
        fi
      fi
    fi
    
    # Create ~/.local/bin if it doesn't exist
    mkdir -p "$HOME/.local/bin"
    
    # Create symlink if needed
    if [ "$install_success" = true ] && [ -n "$binary_name" ] && [ "$binary_name" != "fd" ]; then
      log "INFO" "Creating 'fd' symlink for convenience..."
      ln -sf "$(which $binary_name)" "$HOME/.local/bin/fd"
      
      # Add ~/.local/bin to PATH if it's not already there
      if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log "INFO" "Adding ~/.local/bin to PATH in shell configuration..."
        
        # Determine which shell config file to use
        if [ -n "${BASH_VERSION:-}" ]; then
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        elif [ -n "${ZSH_VERSION:-}" ]; then
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        else
          # Default to bashrc if we can't detect
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        
        # Use the new PATH for the current session
        export PATH="$HOME/.local/bin:$PATH"
      fi
      
      log "SUCCESS" "Created fd symlink in ~/.local/bin/"
    fi
    
    if [ "$install_success" = false ]; then
      log "WARNING" "Could not install fd-find. Standard find will be used instead."
    fi
  fi
  # Special case for eza (successor to exa)
  if ! command -v eza &>/dev/null && [ -n "$(echo "${SELECTED_PACKAGES[@]}" | grep -o "eza")" ]; then
    log "INFO" "Installing eza (modern ls replacement)..."
    
    install_success=false
    
    # Step 1: Try package manager installation based on distro
    case $OS_TYPE in
      debian)
        # Try to add official eza repository for Debian/Ubuntu
        log "INFO" "Setting up eza repository for Debian/Ubuntu..."
        
        # Ensure required tools are installed
        run_with_privileges apt update
        run_with_privileges apt install -y gpg curl wget 2>/dev/null
        
        # Add the eza repository
        run_with_privileges mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | run_with_privileges gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | run_with_privileges tee /etc/apt/sources.list.d/gierens.list >/dev/null
        run_with_privileges chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list 2>/dev/null
        
        # Update and install
        if run_with_privileges apt update && run_with_privileges apt install -y eza; then
          log "SUCCESS" "Installed eza from official repository."
          install_success=true
        else
          log "WARNING" "Failed to install eza from repository."
        fi
        ;;
      redhat)
        # For Fedora, eza is in the official repositories
        if run_with_privileges $PKG_MANAGER install -y eza 2>/dev/null; then
          log "SUCCESS" "Installed eza from official repository."
          install_success=true
        else
          log "WARNING" "Failed to install eza from repository."
        fi
        ;;
      alpine)
        # For Alpine
        if run_with_privileges apk add eza 2>/dev/null; then
          log "SUCCESS" "Installed eza from Alpine repository."
          install_success=true
        else
          log "WARNING" "Failed to install eza from repository."
        fi
        ;;
      *)
        log "INFO" "No predefined repository for this OS. Trying alternative methods."
        ;;
    esac
    
    # Step 2: If package manager failed, try downloading pre-built binary
    if [ "$install_success" = false ]; then
      log "INFO" "Trying to download pre-built binary..."
      
      # Create temp directory for download
      local temp_dir="/tmp/eza_install"
      mkdir -p "$temp_dir"
      cd "$temp_dir"
      
      # Determine system architecture
      local arch="$(uname -m)"
      local target=""
      
      case "$arch" in
        x86_64)
          target="x86_64-unknown-linux-gnu"
          ;;
        aarch64|arm64)
          target="aarch64-unknown-linux-gnu"
          ;;
        *)
          log "WARNING" "Unsupported architecture: $arch"
          ;;
      esac
      
      if [ -n "$target" ]; then
        # Try to download and install the pre-built binary
        if curl -L -o eza.tar.gz "https://github.com/eza-community/eza/releases/latest/download/eza_${target}.tar.gz" 2>/dev/null; then
          tar -xzf eza.tar.gz
          run_with_privileges install -m755 eza /usr/local/bin/eza 2>/dev/null ||
          mkdir -p "$HOME/.local/bin" && install -m755 eza "$HOME/.local/bin/eza"
          
          if command -v eza &>/dev/null; then
            log "SUCCESS" "Installed eza from pre-built binary."
            install_success=true
          else
            log "WARNING" "Failed to install eza binary."
          fi
        else
          log "WARNING" "Failed to download eza binary."
        fi
      fi
      
      # Clean up temp directory
      cd - > /dev/null
      rm -rf "$temp_dir"
    fi
    
    # Step 3: If binary installation failed and cargo is available, try cargo
    if [ "$install_success" = false ] && command -v cargo &>/dev/null; then
      log "INFO" "Trying to install eza via cargo..."
      if cargo install eza; then
        log "SUCCESS" "Installed eza via cargo."
        install_success=true
      else
        log "WARNING" "Failed to install eza via cargo."
      fi
    fi
    
    # If installation succeeded, create exa symlink for backward compatibility
    if [ "$install_success" = true ]; then
      log "INFO" "Creating 'exa' symlink for backward compatibility..."
      if [ "$USER_INSTALL_ONLY" = true ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which eza)" "$HOME/.local/bin/exa" 2>/dev/null
        log "SUCCESS" "Created exa symlink in user's ~/.local/bin directory"
      else
        run_with_privileges ln -sf "$(which eza)" /usr/local/bin/exa 2>/dev/null || {
          mkdir -p "$HOME/.local/bin"
          ln -sf "$(which eza)" "$HOME/.local/bin/exa" 2>/dev/null
          log "SUCCESS" "Created exa symlink in user's ~/.local/bin directory"
        }
      fi
    else
      log "WARNING" "Could not install eza. Standard ls will be used instead."
    fi
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
          run_with_privileges apt install -y bat || run_with_privileges apt install -y batcat
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
      log "INFO" "Installing pfetch..."
      if [ "$USER_INSTALL_ONLY" = true ]; then
        # User-only installation to ~/.local/bin
        mkdir -p "$HOME/.local/bin"
        install -m755 pfetch-master/pfetch "$HOME/.local/bin/pfetch"
        # Make sure ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
          log "INFO" "Adding ~/.local/bin to PATH in shell configuration..."
          if [ -n "${BASH_VERSION:-}" ]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
          elif [ -n "${ZSH_VERSION:-}" ]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
          else
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
          fi
          # Use the new PATH for the current session
          export PATH="$HOME/.local/bin:$PATH"
        fi
        log "INFO" "Installed pfetch to ~/.local/bin/"
      else
        # System-wide installation
        log "INFO" "Installing pfetch to /usr/local/bin/..."
        run_with_privileges install -m755 pfetch-master/pfetch /usr/local/bin/
      fi
      
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
# Function to configure Nerd Font installation
configure_nerd_font() {
  # Skip if non-interactive mode
  if [ "$INTERACTIVE" = false ]; then
    log "INFO" "Using default Nerd Font setting in non-interactive mode: $([ "$INSTALL_NERD_FONT" = true ] && echo "enabled" || echo "disabled")"
    return 0
  fi
  
  echo -e "\n${BOLD}${CYAN}Nerd Font Installation:${NC}"
  
  if [ "$DIALOG_AVAILABLE" = true ]; then
    # Using dialog for selection
    local temp_file=$(mktemp)
    
    dialog --backtitle "ServerCozy v${SCRIPT_VERSION}" \
           --title "Nerd Font Installation" \
           --yesno "Install JetBrainsMono Nerd Font?\n\nNerd Fonts add additional glyphs/icons to enhance terminal appearance.\nRecommended for modern terminal experience." \
           10 60 2> "$temp_file"
    
    local result=$?
    rm -f "$temp_file"
    
    if [ $result -eq 0 ]; then
      INSTALL_NERD_FONT=true
      echo -e "${GREEN}✓${NC} Nerd Font installation ${GREEN}enabled${NC}"
    else
      INSTALL_NERD_FONT=false
      echo -e "${YELLOW}✗${NC} Nerd Font installation ${YELLOW}disabled${NC}"
    fi
  else
    # Text-based selection
    echo -e "Nerd Fonts add additional glyphs/icons to enhance terminal appearance."
    echo -e "Recommended for modern terminal experience.\n"
    echo -e "Install JetBrainsMono Nerd Font?"
    echo -e "1. ${GREEN}Yes${NC} - Install Nerd Font (recommended)"
    echo -e "2. ${YELLOW}No${NC}  - Skip Nerd Font installation"
    
    read -p "> " nerd_font_choice
    
    if [[ "$nerd_font_choice" =~ ^[Yy]|1$ ]]; then
      INSTALL_NERD_FONT=true
      echo -e "${GREEN}✓${NC} Nerd Font installation ${GREEN}enabled${NC}"
    else
      INSTALL_NERD_FONT=false
      echo -e "${YELLOW}✗${NC} Nerd Font installation ${YELLOW}disabled${NC}"
    fi
  fi
  
  log "INFO" "Nerd Font installation $([ "$INSTALL_NERD_FONT" = true ] && echo "enabled" || echo "disabled") by user"
}

# Function to install JetBrainsMono Nerd Font
install_nerd_font() {
  if [ "$INSTALL_NERD_FONT" = false ]; then
    log "INFO" "Skipping Nerd Font installation as per configuration."
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
  
  # Create a backup using our backup function
  backup_config_file "$shell_config"
  
  # Add custom prompt configuration
  if [ -n "${ZSH_VERSION:-}" ]; then
    # ZSH specific prompt configuration
    cat >> "$shell_config" << 'EOF'

# Custom prompt configuration by ServerCozy for ZSH
autoload -Uz colors && colors
autoload -Uz vcs_info
precmd() {
  vcs_info
  if [ $? -eq 0 ]; then
    PROMPT_SYMBOL="%{$fg[green]%}❱%{$reset_color%}"
  else
    PROMPT_SYMBOL="%{$fg[red]%}❱%{$reset_color%}"
  fi
}

# Enable git branch detection
zstyle ':vcs_info:git:*' formats ' (%{$fg[yellow]%}%b%{$reset_color%})'

# Shorten path if it's too long
function collapse_pwd {
  local pwd_length=30
  local pwd_symbol="…"
  local pwd_path="${PWD/#$HOME/~}"
  
  if [ ${#pwd_path} -gt $pwd_length ]; then
    local offset=$(( ${#pwd_path} - $pwd_length ))
    echo "${pwd_symbol}${pwd_path:$offset:$pwd_length}"
  else
    echo "$pwd_path"
  fi
}

# Set the prompt
setopt PROMPT_SUBST
PROMPT='%B%n%b@%B%m%b %{$fg[cyan]%}$(collapse_pwd)%{$reset_color%}${vcs_info_msg_0_} ${PROMPT_SYMBOL} '
EOF
  else
    # Bash prompt configuration
    cat >> "$shell_config" << 'EOF'

# Custom prompt configuration by ServerCozy for Bash
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
    git_branch=" (${YELLOW}${git_branch}${RESET})"  # Show git branch in prompt
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
  fi
  
  log "SUCCESS" "Custom prompt configured."
}

# Function to ask user about Vim configuration
ask_configure_vim() {
  # Skip if non-interactive mode
  if [ "$INTERACTIVE" = false ]; then
    log "INFO" "Using default Vim configuration setting: $([ "$CONFIGURE_VIM" = true ] && echo "enabled" || echo "disabled")"
    return 0
  fi
  
  echo -e "\n${BOLD}${CYAN}Vim Configuration:${NC}"
  
  if [ "$DIALOG_AVAILABLE" = true ]; then
    # Using dialog for selection
    local temp_file=$(mktemp)
    
    dialog --backtitle "ServerCozy v${SCRIPT_VERSION}" \
           --title "Vim Configuration" \
           --defaultno \
           --yesno "Configure Vim with enhanced settings?\n\nThis will create a .vimrc file with useful defaults." \
           10 60 2> "$temp_file"
    
    local result=$?
    rm -f "$temp_file"
    
    if [ $result -eq 0 ]; then
      CONFIGURE_VIM=true
      echo -e "${GREEN}✓${NC} Vim configuration ${GREEN}enabled${NC}"
    else
      CONFIGURE_VIM=false
      echo -e "${YELLOW}✗${NC} Vim configuration ${YELLOW}disabled${NC}"
    fi
  else
    # Text-based selection with yes as default
    echo -e "Configure Vim with enhanced settings?"
    echo -e "This will create a .vimrc file with useful defaults."
    echo -e "1. ${GREEN}Yes${NC} - Configure Vim (default)"
    echo -e "2. ${YELLOW}No${NC}  - Skip Vim configuration"
    
    read -p "> " vim_choice
    
    # Default to yes if nothing entered
    if [[ -z "$vim_choice" || "$vim_choice" =~ ^[Yy]|1$ ]]; then
      CONFIGURE_VIM=true
      echo -e "${GREEN}✓${NC} Vim configuration ${GREEN}enabled${NC}"
    else
      CONFIGURE_VIM=false
      echo -e "${YELLOW}✗${NC} Vim configuration ${YELLOW}disabled${NC}"
    fi
  fi
  
  log "INFO" "Vim configuration $([ "$CONFIGURE_VIM" = true ] && echo "enabled" || echo "disabled") by user"
}

# Function to ask user about aliases configuration
ask_configure_aliases() {
  # Skip if non-interactive mode
  if [ "$INTERACTIVE" = false ]; then
    log "INFO" "Using default aliases configuration setting: $([ "$CONFIGURE_ALIASES" = true ] && echo "enabled" || echo "disabled")"
    return 0
  fi
  
  echo -e "\n${BOLD}${CYAN}Aliases Configuration:${NC}"
  
  if [ "$DIALOG_AVAILABLE" = true ]; then
    # Using dialog for selection
    local temp_file=$(mktemp)
    
    dialog --backtitle "ServerCozy v${SCRIPT_VERSION}" \
           --title "Aliases Configuration" \
           --defaultno \
           --yesno "Configure useful command aliases?\n\nThis will create alias shortcuts for commonly used commands." \
           10 60 2> "$temp_file"
    
    local result=$?
    rm -f "$temp_file"
    
    if [ $result -eq 0 ]; then
      CONFIGURE_ALIASES=true
      echo -e "${GREEN}✓${NC} Aliases configuration ${GREEN}enabled${NC}"
    else
      CONFIGURE_ALIASES=false
      echo -e "${YELLOW}✗${NC} Aliases configuration ${YELLOW}disabled${NC}"
    fi
  else
    # Text-based selection with yes as default
    echo -e "Configure useful command aliases?"
    echo -e "This will create alias shortcuts for commonly used commands."
    echo -e "1. ${GREEN}Yes${NC} - Configure aliases (default)"
    echo -e "2. ${YELLOW}No${NC}  - Skip aliases configuration"
    
    read -p "> " aliases_choice
    
    # Default to yes if nothing entered
    if [[ -z "$aliases_choice" || "$aliases_choice" =~ ^[Yy]|1$ ]]; then
      CONFIGURE_ALIASES=true
      echo -e "${GREEN}✓${NC} Aliases configuration ${GREEN}enabled${NC}"
    else
      CONFIGURE_ALIASES=false
      echo -e "${YELLOW}✗${NC} Aliases configuration ${YELLOW}disabled${NC}"
    fi
  fi
  
  log "INFO" "Aliases configuration $([ "$CONFIGURE_ALIASES" = true ] && echo "enabled" || echo "disabled") by user"
}

# Function to configure useful aliases
configure_aliases() {
  if [ "$CONFIGURE_ALIASES" = false ]; then
    return 0
  fi
  
  log "INFO" "Configuring useful aliases..."
  
  # Detect shell
  local aliases_file="$HOME/.bash_aliases"
  if [ -n "${ZSH_VERSION:-}" ]; then
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
  
  # Backup existing aliases file if it exists
  backup_config_file "$aliases_file" || true  # Ignore return value when file doesn't exist
  
  # Create/update aliases file
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
if command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -alF --icons'
  alias lt='eza -T --icons'
elif command -v exa &>/dev/null; then
  # Backward compatibility for exa
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
elif command -v neofetch &>/dev/null; then
  alias sysinfo='neofetch'
else
  # OS-specific fallback commands for system info
  case "$(uname)" in
    Darwin)
      # macOS specific commands
      alias sysinfo='echo -e "\n$(hostname) $(date)" && echo -e "macOS $(sw_vers -productVersion)" && echo -e "\nKernel: $(uname -r)" && echo -e "Memory: $(vm_stat | grep "Pages active" | awk "{ print \$3 }" | sed "s/\.//")" && echo -e "Disk: $(df -h / | grep / | awk "{print \$4\"/\"\$2}")"'
      ;;
    Linux)
      # Check if /etc/*release exists
      if [ -f /etc/os-release ]; then
        alias sysinfo='echo -e "\n$(hostname) $(date)" && cat /etc/os-release | grep -E "^(NAME|VERSION)=" && echo -e "\nKernel: $(uname -r)" && echo -e "Memory: $(free -h | grep Mem | awk "{print \$3\"/\"\$2}")" && echo -e "Disk: $(df -h / | grep / | awk "{print \$3\"/\"\$2}")"'
      else
        alias sysinfo='echo -e "\n$(hostname) $(date)" && echo -e "Linux $(uname -r)" && echo -e "Memory: $(free -h | grep Mem | awk "{print \$3\"/\"\$2}")" && echo -e "Disk: $(df -h / | grep / | awk "{print \$3\"/\"\$2}")"'
      fi
      ;;
    FreeBSD|OpenBSD|NetBSD)
      # BSD variants
      alias sysinfo='echo -e "\n$(hostname) $(date)" && echo -e "$(uname -s) $(uname -r)" && echo -e "\nKernel: $(uname -r)" && echo -e "Disk: $(df -h / | grep / | awk "{print \$3\"/\"\$2}")"'
      ;;
    *)
      # Generic fallback
      alias sysinfo='echo -e "\n$(hostname) $(date)" && echo -e "$(uname -s) $(uname -r)" && echo -e "\nKernel: $(uname -r)"'
      ;;
  esac
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
  
  # Backup existing .vimrc if it exists
  backup_config_file "$HOME/.vimrc" || true  # Ignore return value when file doesn't exist
  
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
  # Calculate elapsed time if start_time is set
  local elapsed_time=""
  if [ -n "$start_time" ]; then
    local end_time=$(date +%s)
    local total_seconds=$((end_time - start_time))
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    elapsed_time=" in ${minutes}m ${seconds}s"
  fi

  echo -e "\n${BOLD}${GREEN}=== ServerCozy Setup Complete${elapsed_time} ===${NC}"
  echo -e "${BOLD}The following improvements have been made:${NC}"
  
  # Check installed packages
  echo -e "\n${BOLD}Installed Tools:${NC}"
  
  local all_tools=("${ESSENTIAL_TOOLS[@]}" "${RECOMMENDED_TOOLS[@]}" "${ADVANCED_TOOLS[@]}")
  local installed_count=0
  
  # Temporarily silence the debugging logs
  LOG_DEBUG_TEMP="$LOG_DEBUG"
  LOG_DEBUG=false
  
  for tool in "${all_tools[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    # Check for installation without triggering debug logs
    if command -v "$pkg" &>/dev/null || grep -q "ii  $pkg " <<< "$(dpkg -l 2>/dev/null)" || type "$pkg" &>/dev/null; then
      echo -e "  ${GREEN}✓${NC} $pkg - $desc"
      installed_count=$((installed_count+1))
    fi
  done
  
  # Restore debug setting
  LOG_DEBUG="$LOG_DEBUG_TEMP"
  
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

# Function to check for dialog and install if needed
check_dialog() {
  log "INFO" "Checking for dialog utility..."
  
  if [ "$USE_DIALOG" = false ]; then
    log "INFO" "Dialog TUI disabled by user preference."
    DIALOG_AVAILABLE=false
    return 0
  fi
  
  if command -v dialog &>/dev/null; then
    # Check if dialog actually works by running a simple test
    if dialog --version >/dev/null 2>&1; then
      # Further test if dialog can create a UI
      if echo "test" | dialog --inputbox "Testing dialog..." 8 40 2>/dev/null; then
        log "SUCCESS" "Dialog utility found and working properly."
        DIALOG_AVAILABLE=true
        return 0
      else
        log "WARNING" "Dialog command found but not working properly in this environment."
        DIALOG_AVAILABLE=false
      fi
    else
      log "WARNING" "Dialog command found but not functioning."
      DIALOG_AVAILABLE=false
    fi
  else
    log "INFO" "Dialog utility not found."
    DIALOG_AVAILABLE=false
  fi
  
  # If we get here, either dialog is not installed or not working
  echo -e "\n${YELLOW}${BOLD}Dialog TUI not available${NC}"
  echo -e "Falling back to text-based interface."
  echo -e "This may be due to terminal limitations or SSH connection settings."
  echo
  
  # Ask if user wants to install dialog only if it's not installed
  if ! command -v dialog &>/dev/null; then
    echo -e "Would you like to install dialog? (y/n)"
    echo -e "1. ${GREEN}Yes${NC} - Install dialog (might still not work in this environment)"
    echo -e "2. ${YELLOW}No${NC}  - Continue with basic text interface"
    
    read -p "> " install_dialog
    
    if [[ "$install_dialog" =~ ^[Yy]|1$ ]]; then
      log "INFO" "Installing dialog..."
      
      case $PKG_MANAGER in
        apt)
          run_with_privileges apt install -y dialog
          ;;
        dnf|yum)
          run_with_privileges $PKG_MANAGER install -y dialog
          ;;
        apk)
          run_with_privileges apk add dialog
          ;;
        brew)
          brew install dialog
          ;;
        pacman)
          run_with_privileges pacman -S --noconfirm dialog
          ;;
        pkg)
          run_with_privileges pkg install -y dialog
          ;;
      esac
      
      # Check again if dialog works after installation
      if command -v dialog &>/dev/null && dialog --version >/dev/null 2>&1; then
        if echo "test" | dialog --inputbox "Testing dialog..." 8 40 2>/dev/null; then
          log "SUCCESS" "Dialog installed and working successfully."
          DIALOG_AVAILABLE=true
          return 0
        fi
      fi
      
      log "WARNING" "Dialog installed but not working in this environment. Using text-based interface."
      DIALOG_AVAILABLE=false
    else
      log "INFO" "Continuing without dialog. Using text-based interface."
      DIALOG_AVAILABLE=false
    fi
  fi
}

# Function to check privileges and set up the appropriate command
check_sudo() {
  log "INFO" "Checking for privileged command access..."
  
  # Initialize empty SUDO_CMD as a fallback
  SUDO_CMD=""
  SUDO_AVAILABLE=false
  DOAS_AVAILABLE=false
  USER_INSTALL_ONLY=false

  # Check for sudo availability
  if command_exists sudo; then
    # Test sudo access
    if sudo -n true 2>/dev/null; then
      log "SUCCESS" "sudo access confirmed (passwordless)."
      SUDO_CMD="sudo"
      SUDO_AVAILABLE=true
      return 0
    elif sudo true; then
      log "SUCCESS" "sudo access confirmed with password."
      SUDO_CMD="sudo"
      SUDO_AVAILABLE=true
      return 0
    else
      log "WARNING" "sudo command found but access failed."
    fi
  else
    log "WARNING" "sudo command not found."
  fi

  # If sudo failed or not available, try doas (common on BSD systems)
  if command_exists doas; then
    log "INFO" "Found doas, trying to use it instead of sudo..."
    if doas true 2>/dev/null; then
      log "SUCCESS" "doas access confirmed."
      SUDO_CMD="doas"
      DOAS_AVAILABLE=true
      return 0
    else
      log "WARNING" "doas command found but access failed."
    fi
  fi

  # If neither sudo nor doas is available, check if user is root
  if [ "$(id -u)" -eq 0 ]; then
    log "SUCCESS" "Running as root user, no sudo needed."
    SUDO_CMD=""
    return 0
  fi

  # Ask if user wants to continue without privileged access
  echo
  echo -e "${YELLOW}${BOLD}No privileged access method available${NC}"
  echo -e "Without sudo or doas, some features may not work correctly."
  echo -e "You can continue with user-only installation, but some tools may not be installed system-wide."
  echo -e "1. ${GREEN}Continue${NC} - Try user-only installation where possible"
  echo -e "2. ${RED}Abort${NC} - Exit and install sudo or gain proper permissions"
  echo
  read -p "Enter choice [1/2]: " privilege_choice
  
  if [[ "$privilege_choice" == "1" ]]; then
    log "WARNING" "Continuing with user-only installation mode."
    USER_INSTALL_ONLY=true
    return 0
  else
    log "ERROR" "Exiting due to lack of privileged access."
    exit 1
  fi
}

# Function to execute a command with appropriate privileges
run_with_privileges() {
  local cmd="$@"
  
  if [ "$USER_INSTALL_ONLY" = true ]; then
    log "WARNING" "Skipping privileged command: $cmd"
    return 1
  elif [ -n "$SUDO_CMD" ]; then
    $SUDO_CMD $cmd
    return $?
  elif [ "$(id -u)" -eq 0 ]; then
    $cmd
    return $?
  else
    log "ERROR" "Cannot run privileged command: $cmd"
    return 1
  fi
}

# Function to update installation progress
update_progress() {
  installation_step="$1"
  log "INFO" "Starting step: $installation_step"
}

# Function to handle macOS-specific setup
setup_macos() {
  if [ "$OS_TYPE" != "macos" ]; then
    return 0
  fi
  
  log "INFO" "Performing macOS-specific setup..."
  
  # Check if Homebrew is installed
  if ! command_exists brew; then
    log "INFO" "Homebrew not found. Recommending installation..."
    echo -e "\n${YELLOW}${BOLD}Homebrew is not installed${NC}"
    echo -e "Homebrew is highly recommended for installing packages on macOS."
    echo -e "Would you like to install Homebrew? (y/n)"
    read -p "> " install_homebrew
    
    if [[ "$install_homebrew" =~ ^[Yy]$ ]]; then
      log "INFO" "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      
      # Check installation
      if command_exists brew; then
        log "SUCCESS" "Homebrew installed successfully."
        PKG_MANAGER="brew"
      else
        log "ERROR" "Failed to install Homebrew. Some features may not work."
        PKG_MANAGER="none"
      fi
    else
      log "WARNING" "Skipping Homebrew installation. Some features may not work."
      PKG_MANAGER="none"
    fi
  fi
  
  # macOS specific tool adjustments
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    # Check for missing but useful macOS tools
    if ! command_exists coreutils; then
      echo -e "\n${YELLOW}GNU coreutils not detected. These provide many standard Linux utilities.${NC}"
      echo -e "Would you like to install GNU coreutils? (y/n)"
      read -p "> " install_coreutils
      
      if [[ "$install_coreutils" =~ ^[Yy]$ ]]; then
        brew install coreutils
        log "SUCCESS" "GNU coreutils installed"
      fi
    fi
  fi
  
  return 0
}

# Function to create a dialog-based welcome screen
show_welcome_screen() {
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Welcome to ServerCozy\Zn" \
         --msgbox "\n\Z1ServerCozy v${SCRIPT_VERSION}\Zn\n\nThis script enhances a cloud server environment with useful tools and configurations.\nIt automates the installation of common utilities, shell improvements, and productivity tools.\n\nAuthor: Sudharsan Ananth\n\n\Z4Page 1/6\Zn" \
         $dialog_height $dialog_width
  
  return $?
}

# Function to check prerequisites and show system information
show_prerequisites_screen() {
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  # Set up logging
  echo "=== ServerCozy Log $(date) ===" > "$LOG_FILE"
  
  # Temporarily redirect stdout to log file for system checks
  # but keep stderr to terminal for any critical errors
  exec 3>&1
  exec 1>>$LOG_FILE
  
  # Check for privileges (sudo/doas)
  update_progress "Checking for privileged access"
  check_sudo
  
  # Detect operating system
  update_progress "Detecting operating system"
  detect_os
  
  # Detect architecture
  update_progress "Detecting system architecture"
  detect_arch
  
  # Check connectivity
  update_progress "Checking internet connectivity"
  check_connectivity
  
  # Update package repositories
  update_progress "Updating package repositories"
  update_package_repos
  
  # Check for dialog availability
  update_progress "Checking for dialog utility"
  check_dialog
  
  # Handle macOS specific setup if needed
  if [ "$OS_TYPE" = "macos" ]; then
    update_progress "Setting up macOS environment"
    setup_macos
  fi
  
  # Restore stdout
  exec 1>&3
  
  # Create system info message
  local system_info="System Information:\n"
  system_info+="- Operating System: ${OS_NAME} ${OS_VERSION}\n"
  system_info+="- Architecture: ${ARCH_TYPE}\n"
  system_info+="- Package Manager: ${PKG_MANAGER}\n"
  system_info+="- Internet Connectivity: $(check_connectivity > /dev/null 2>&1 && echo "Available" || echo "Limited/Not Available")\n"
  system_info+="- Privileged Access: $([ -n "$SUDO_CMD" ] && echo "Available (${SUDO_CMD})" || echo "Not Available")\n"
  
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1System Prerequisites\Zn" \
         --msgbox "\n${system_info}\n\nAll prerequisites have been checked. Ready to proceed with installation.\n\n\Z4Page 2/6\Zn" \
         $dialog_height $dialog_width
  
  return $?
}

# Function to select packages using dialog
tui_select_packages() {
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  local list_height=$((dialog_height - 10))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  # Clear the global array
  SELECTED_PACKAGES=()
  
  # Arrays to store selected indexes
  local essential_selected=()
  local recommended_selected=()
  local advanced_selected=()
  
  # Prepare dialog options for essential tools
  local essential_options=()
  for i in "${!ESSENTIAL_TOOLS[@]}"; do
    IFS=':' read -r item desc <<< "${ESSENTIAL_TOOLS[$i]}"
    essential_options+=("$item" "$desc" "ON")
  done
  
  # Show essential tools selection
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Essential Tools\Zn" \
         --checklist "\nSelect essential tools to install:\n\n\Z4Page 3/6\Zn" \
         $dialog_height $dialog_width $list_height \
         "${essential_options[@]}" 2> /tmp/servercozy_essential
  
  # Read selections
  if [ -f /tmp/servercozy_essential ]; then
    local selections=$(cat /tmp/servercozy_essential)
    for selected in $selections; do
      selected=${selected//\"/}
      for i in "${!ESSENTIAL_TOOLS[@]}"; do
        IFS=':' read -r item desc <<< "${ESSENTIAL_TOOLS[$i]}"
        if [ "$item" = "$selected" ]; then
          essential_selected+=($i)
          SELECTED_PACKAGES+=("${ESSENTIAL_TOOLS[$i]}")
          break
        fi
      done
    done
    rm -f /tmp/servercozy_essential
  fi
  
  # Prepare dialog options for recommended tools
  local recommended_options=()
  for i in "${!RECOMMENDED_TOOLS[@]}"; do
    IFS=':' read -r item desc <<< "${RECOMMENDED_TOOLS[$i]}"
    recommended_options+=("$item" "$desc" "ON")
  done
  
  # Show recommended tools selection
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Recommended Tools\Zn" \
         --checklist "\nSelect recommended tools to install:\n\n\Z4Page 4/6\Zn" \
         $dialog_height $dialog_width $list_height \
         "${recommended_options[@]}" 2> /tmp/servercozy_recommended
  
  # Read selections
  if [ -f /tmp/servercozy_recommended ]; then
    local selections=$(cat /tmp/servercozy_recommended)
    for selected in $selections; do
      selected=${selected//\"/}
      for i in "${!RECOMMENDED_TOOLS[@]}"; do
        IFS=':' read -r item desc <<< "${RECOMMENDED_TOOLS[$i]}"
        if [ "$item" = "$selected" ]; then
          recommended_selected+=($i)
          SELECTED_PACKAGES+=("${RECOMMENDED_TOOLS[$i]}")
          break
        fi
      done
    done
    rm -f /tmp/servercozy_recommended
  fi
  
  # Prepare dialog options for advanced tools
  local advanced_options=()
  for i in "${!ADVANCED_TOOLS[@]}"; do
    IFS=':' read -r item desc <<< "${ADVANCED_TOOLS[$i]}"
    advanced_options+=("$item" "$desc" "OFF")
  done
  
  # Show advanced tools selection
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Advanced Tools\Zn" \
         --checklist "\nSelect advanced tools to install:\n\n\Z4Page 5/6\Zn" \
         $dialog_height $dialog_width $list_height \
         "${advanced_options[@]}" 2> /tmp/servercozy_advanced
  
  # Read selections
  if [ -f /tmp/servercozy_advanced ]; then
    local selections=$(cat /tmp/servercozy_advanced)
    for selected in $selections; do
      selected=${selected//\"/}
      for i in "${!ADVANCED_TOOLS[@]}"; do
        IFS=':' read -r item desc <<< "${ADVANCED_TOOLS[$i]}"
        if [ "$item" = "$selected" ]; then
          advanced_selected+=($i)
          SELECTED_PACKAGES+=("${ADVANCED_TOOLS[$i]}")
          break
        fi
      done
    done
    rm -f /tmp/servercozy_advanced
  fi
  
  return 0
}

# Function to configure options using dialog
tui_configure_options() {
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  local list_height=$((dialog_height - 10))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  # Prepare dialog options
  local options=(
    "nerd_font" "Install JetBrainsMono Nerd Font" "ON"
    "vim_config" "Configure Vim with enhanced settings" "ON"
    "aliases" "Configure useful command aliases" "ON"
  )
  
  # Show options selection
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Configuration Options\Zn" \
         --checklist "\nSelect configuration options:\n\n\Z4Page 6/6\Zn" \
         $dialog_height $dialog_width $list_height \
         "${options[@]}" 2> /tmp/servercozy_options
  
  # Read selections
  if [ -f /tmp/servercozy_options ]; then
    local selections=$(cat /tmp/servercozy_options)
    
    # Default all to false
    INSTALL_NERD_FONT=false
    CONFIGURE_VIM=false
    CONFIGURE_ALIASES=false
    
    # Set selected options to true
    for selected in $selections; do
      selected=${selected//\"/}
      case "$selected" in
        "nerd_font")
          INSTALL_NERD_FONT=true
          ;;
        "vim_config")
          CONFIGURE_VIM=true
          ;;
        "aliases")
          CONFIGURE_ALIASES=true
          ;;
      esac
    done
    
    rm -f /tmp/servercozy_options
  fi
  
  return 0
}

# Function to show installation progress using dialog gauge
tui_install_packages() {
  # Count total operations
  local total_operations=${#SELECTED_PACKAGES[@]}
  [ "$INSTALL_NERD_FONT" = true ] && total_operations=$((total_operations + 1))
  [ "$CONFIGURE_VIM" = true ] && total_operations=$((total_operations + 1))
  [ "$CONFIGURE_ALIASES" = true ] && total_operations=$((total_operations + 1))
  total_operations=$((total_operations + 1)) # For shell prompt configuration
  total_operations=$((total_operations + 1)) # For special package handling
  
  # Ensure at least one operation to avoid division by zero
  [ $total_operations -eq 0 ] && total_operations=1
  
  # Create a temporary file for progress updates
  local progress_file=$(mktemp)
  local message_file=$(mktemp)
  
  # Initialize progress files
  echo "0" > "$progress_file"
  echo "Preparing installation..." > "$message_file"
  
  # Save original stdout/stderr
  exec 3>&1 4>&2
  
  # Function to update progress
  update_progress_gauge() {
    local current="$1"
    local message="$2"
    local percent=$((current * 100 / total_operations))
    
    # Update the progress file
    echo "$percent" > "$progress_file"
    echo "$message" > "$message_file"
    
    # Log the progress to the log file only
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Installation progress: $percent% - $message" >> "$LOG_FILE"
  }
  
  # Start the background process to display the gauge
  (
    while true; do
      # Read current progress
      [ -f "$progress_file" ] && percent=$(cat "$progress_file")
      [ -f "$message_file" ] && message=$(cat "$message_file")
      
      # Display the gauge percentage and message
      echo "$percent"
      echo "XXX"
      echo "$message"
      echo "XXX"
      
      # Sleep briefly to reduce CPU usage
      sleep 0.2
      
      # Exit if we've reached 100% or files are gone
      [ ! -f "$progress_file" ] && break
      [ "$percent" -ge 100 ] && break
    done
  ) | dialog --backtitle "ServerCozy v${SCRIPT_VERSION}" \
             --title "Installation Progress" \
             --gauge "" 10 70 0
  
  # Redirect stdout/stderr to log file for installation operations
  exec 1>>$LOG_FILE 2>>$LOG_FILE
  
  # Install packages with progress updates
  local current=0
  
  # Initial progress
  update_progress_gauge "$current" "Preparing installation..."
  
  # Install selected packages
  for tool in "${SELECTED_PACKAGES[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    current=$((current + 1))
    
    update_progress_gauge "$current" "Installing: $pkg - $desc"
    install_package "$pkg" "$desc"
  done
  
  # Handle special package cases
  current=$((current + 1))
  update_progress_gauge "$current" "Handling special package cases..."
  handle_special_packages
  
  # Configure shell prompt
  current=$((current + 1))
  update_progress_gauge "$current" "Configuring shell prompt..."
  configure_prompt
  
  # Install Nerd Font if selected
  if [ "$INSTALL_NERD_FONT" = true ]; then
    current=$((current + 1))
    update_progress_gauge "$current" "Installing JetBrainsMono Nerd Font..."
    install_nerd_font
  fi
  
  # Configure Vim if selected
  if [ "$CONFIGURE_VIM" = true ]; then
    current=$((current + 1))
    update_progress_gauge "$current" "Configuring Vim..."
    configure_vim
  fi
  
  # Configure aliases if selected
  if [ "$CONFIGURE_ALIASES" = true ]; then
    current=$((current + 1))
    update_progress_gauge "$current" "Configuring useful aliases..."
    configure_aliases
  fi
  
  # Complete
  update_progress_gauge "$total_operations" "Installation complete!"
  
  # Wait for gauge to reach 100%
  sleep 2
  
  # Restore original stdout/stderr
  exec 1>&3 2>&4
  
  # Clean up
  rm -f "$progress_file" "$message_file"
  
  return 0
}

# Function to show installation summary using dialog
tui_show_summary() {
  local term_height=$(tput lines)
  local term_width=$(tput cols)
  local dialog_height=$((term_height * 3 / 4))
  local dialog_width=$((term_width * 3 / 4))
  
  # Ensure minimum dimensions
  [ $dialog_height -lt 20 ] && dialog_height=20
  [ $dialog_width -lt 75 ] && dialog_width=75
  
  # Calculate elapsed time
  local elapsed_time=""
  if [ -n "$start_time" ]; then
    local end_time=$(date +%s)
    local total_seconds=$((end_time - start_time))
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    elapsed_time=" in ${minutes}m ${seconds}s"
  fi
  
  # Build summary message
  local summary="ServerCozy Setup Complete${elapsed_time}\n\n"
  summary+="The following improvements have been made:\n\n"
  
  # Installed tools
  summary+="Installed Tools:\n"
  local all_tools=("${ESSENTIAL_TOOLS[@]}" "${RECOMMENDED_TOOLS[@]}" "${ADVANCED_TOOLS[@]}")
  local installed_count=0
  
  # Temporarily silence the debugging logs
  LOG_DEBUG_TEMP="$LOG_DEBUG"
  LOG_DEBUG=false
  
  for tool in "${all_tools[@]}"; do
    IFS=':' read -r pkg desc <<< "$tool"
    # Check for installation without triggering debug logs
    if command -v "$pkg" &>/dev/null || grep -q "ii  $pkg " <<< "$(dpkg -l 2>/dev/null)" || type "$pkg" &>/dev/null; then
      summary+="  ✓ $pkg - $desc\n"
      installed_count=$((installed_count+1))
    fi
  done
  
  # Restore debug setting
  LOG_DEBUG="$LOG_DEBUG_TEMP"
  
  if [ $installed_count -eq 0 ]; then
    summary+="  No tools were installed.\n"
  fi
  
  # Shell customizations
  summary+="\nShell Customizations:\n"
  if [ "$CONFIGURE_PROMPT" = true ]; then
    summary+="  ✓ Custom prompt installed\n"
  fi
  if [ "$CONFIGURE_ALIASES" = true ]; then
    summary+="  ✓ Useful aliases configured\n"
  fi
  if [ "$CONFIGURE_VIM" = true ]; then
    summary+="  ✓ Vim configured\n"
  fi
  if [ "$INSTALL_NERD_FONT" = true ]; then
    summary+="  ✓ JetBrainsMono Nerd Font installed\n"
  fi
  
  summary+="\nTo apply all changes, either:\n"
  summary+="  1. Log out and log back in\n"
  summary+="  2. Run: source ~/.bashrc (or ~/.zshrc if using zsh)\n\n"
  summary+="For more information, type: help\n"
  summary+="Log file saved to: $LOG_FILE"
  
  dialog --colors \
         --backtitle "ServerCozy v${SCRIPT_VERSION}" \
         --title "\Z1Installation Summary\Zn" \
         --msgbox "\n$summary\n" \
         $dialog_height $dialog_width
  
  return 0
}

# Function to run the text-based interface workflow
run_text_interface() {
  echo -e "\n${BOLD}${CYAN}=== ServerCozy v${SCRIPT_VERSION} ===${NC}"
  echo -e "This script enhances your server environment with useful tools and configurations."
  
  # Check prerequisites
  echo -e "\n${BOLD}${CYAN}Checking system prerequisites...${NC}"
  
  # Redirect stdout to log file for system checks
  exec 3>&1
  exec 1>>$LOG_FILE
  
  # Check for privileges (sudo/doas)
  update_progress "Checking for privileged access"
  check_sudo
  
  # Detect operating system
  update_progress "Detecting operating system"
  detect_os
  
  # Detect architecture
  update_progress "Detecting system architecture"
  detect_arch
  
  # Check connectivity
  update_progress "Checking internet connectivity"
  check_connectivity
  
  # Update package repositories
  update_progress "Updating package repositories"
  update_package_repos
  
  # Restore stdout
  exec 1>&3
  
  # Display system info
  echo -e "\n${BOLD}System Information:${NC}"
  echo -e "- Operating System: ${OS_NAME} ${OS_VERSION}"
  echo -e "- Architecture: ${ARCH_TYPE}"
  echo -e "- Package Manager: ${PKG_MANAGER}"
  echo -e "- Internet Connectivity: $(check_connectivity > /dev/null 2>&1 && echo "Available" || echo "Limited/Not Available")"
  echo -e "- Privileged Access: $([ -n "$SUDO_CMD" ] && echo "Available (${SUDO_CMD})" || echo "Not Available")"
  
  # Package selection
  echo -e "\n${BOLD}${CYAN}Select packages to install:${NC}"
  select_packages
  
  # Configure options
  configure_nerd_font
  ask_configure_vim
  ask_configure_aliases
  
  # Install packages and configure
  echo -e "\n${BOLD}${CYAN}Installing selected packages and configuring system...${NC}"
  
  # Redirect stdout/stderr to log file for installation
  exec 3>&1 4>&2
  exec 1>>$LOG_FILE 2>>$LOG_FILE
  
  # Configure shell prompt
  configure_prompt
  
  # Install Nerd Font if selected
  if [ "$INSTALL_NERD_FONT" = true ]; then
    install_nerd_font
  fi
  
  # Configure Vim if selected
  if [ "$CONFIGURE_VIM" = true ]; then
    configure_vim
  fi
  
  # Configure aliases if selected
  if [ "$CONFIGURE_ALIASES" = true ]; then
    configure_aliases
  fi
  
  # Handle special package cases
  handle_special_packages
  
  # Restore stdout/stderr
  exec 1>&3 2>&4
  
  # Show summary
  show_summary
}

# Main function with workflow selection
main() {
  # Store start time for elapsed time calculation
  local start_time=$(date +%s)
  
  # Check lock file to prevent multiple instances
  check_lock
  
  # Check if script is executable
  update_progress "Checking script permissions"
  check_executable
  
  # Set up logging
  echo "=== ServerCozy Log $(date) ===" > "$LOG_FILE"
  
  # Check for dialog availability
  check_dialog
  
  # Choose workflow based on dialog availability
  if [ "$DIALOG_AVAILABLE" = true ]; then
    # TUI workflow
    show_welcome_screen
    show_prerequisites_screen
    tui_select_packages
    tui_configure_options
    tui_install_packages
    tui_show_summary
  else
    # Text-based interface
    run_text_interface
  fi
  
  log "SUCCESS" "Installation completed successfully!"
}

# Function to check for updates to the script using dialog
check_for_updates() {
  if [ "$SKIP_UPDATE_CHECK" = true ]; then
    log "INFO" "Update check skipped due to command line flag"
    return 0
  fi
  
  log "INFO" "Checking for script updates..."
  
  # Define remote repo URL
  local repo_url="https://raw.githubusercontent.com/sudharsan-007/servercozy/main/server-cozy.sh"
  local temp_script="/tmp/server-cozy-latest.sh"
  
  # Download the latest version
  if ! download_file "$repo_url" "$temp_script" 2 3; then
    log "WARNING" "Failed to check for updates. Continuing with current version."
    return 1
  fi
  
  # Extract version from downloaded script
  local remote_version=$(grep -o '^VERSION="[0-9\.]*"' "$temp_script" | cut -d'"' -f2)
  
  if [ -z "$remote_version" ]; then
    log "WARNING" "Could not determine remote version. Continuing with current version."
    rm -f "$temp_script"
    return 1
  fi
  
  # Log version information
  log "INFO" "Script version: $SCRIPT_VERSION, Latest version: $remote_version"
  log "INFO" "OS version: $OS_NAME $OS_VERSION"
  
  # Compare versions (basic string comparison - assumes semantic versioning)
  if [ "$SCRIPT_VERSION" != "$remote_version" ]; then
    # Display update notification using dialog
    local term_height=$(tput lines)
    local term_width=$(tput cols)
    local dialog_height=$((term_height * 3 / 4))
    local dialog_width=$((term_width * 3 / 4))
    
    # Ensure minimum dimensions
    [ $dialog_height -lt 20 ] && dialog_height=20
    [ $dialog_width -lt 75 ] && dialog_width=75
    
    dialog --colors \
           --backtitle "ServerCozy v${SCRIPT_VERSION}" \
           --title "\Z1Update Available\Zn" \
           --yesno "\nA new version of ServerCozy is available!\n\nCurrent version: $SCRIPT_VERSION\nLatest version: $remote_version\n\nWould you like to update to the latest version?" \
           $dialog_height $dialog_width
    
    local result=$?
    
    if [ $result -eq 0 ]; then
      log "INFO" "Updating to version $remote_version"
      
      # Make new script executable
      chmod +x "$temp_script"
      
      # Create backup of current script
      local backup_script="${0}.backup.$(date +%Y%m%d%H%M%S)"
      cp "$0" "$backup_script"
      log "INFO" "Created backup of current script at $backup_script"
      
      # Replace current script with new one
      if cp "$temp_script" "$0"; then
        log "SUCCESS" "Successfully updated to version $remote_version"
        
        dialog --colors \
               --backtitle "ServerCozy v${SCRIPT_VERSION}" \
               --title "\Z1Update Successful\Zn" \
               --msgbox "\nUpdate successful! The script will now restart with the new version." \
               $dialog_height $dialog_width
        
        exec "$0" "$@" --skip-update
        # Script execution will stop here and restart with new version
      else
        log "ERROR" "Failed to update script due to permissions. Try running with sudo."
        
        dialog --colors \
               --backtitle "ServerCozy v${SCRIPT_VERSION}" \
               --title "\Z1Update Failed\Zn" \
               --msgbox "\nFailed to update script due to permissions.\nPlease try running with sudo or manually downloading the latest version." \
               $dialog_height $dialog_width
      fi
    else
      log "INFO" "Update skipped by user. Continuing with current version."
    fi
  else
    log "INFO" "You are running the latest version ($SCRIPT_VERSION)."
  fi
  
  # Clean up
  rm -f "$temp_script"
  return 0
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
    --no-dialog)
      USE_DIALOG=false
      shift
      ;;
    --user-only)
      USER_INSTALL_ONLY=true
      log "INFO" "User-only mode enabled. System-wide installations will be skipped."
      shift
      ;;
    --no-nerd-font)
      INSTALL_NERD_FONT=false
      log "INFO" "Nerd Font installation will be skipped."
      shift
      ;;
    --skip-update)
      SKIP_UPDATE_CHECK=true
      shift
      ;;
    -v|--version)
      echo "ServerCozy v${SCRIPT_VERSION}"
      exit 0
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
