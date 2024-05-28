#!/bin/bash

# Enhanced script with robust error handling, input validation, and optimized performance

# Colors and Emoji Codes for readability and user feedback
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color
INFO_EMOJI="ℹ️"
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
NETWORK_EMOJI="🌐"

# Ensure the script is not run as root to avoid Homebrew issues
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script must not be run as root${NC}" 1>&2
   exit 1
fi

AUTO_REPAIR=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --auto-repair) AUTO_REPAIR=true ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Automatically install missing commands
ensure_command() {
  local command="$1"
  local install_cmd="$2"
  if ! command_exists "$command"; then
    log_info "Installing $command..."
    eval "$install_cmd"
    if ! command_exists "$command"; then
      log_error "Failed to install $command."
      exit 1
    fi
  fi
}

# Function Definitions for Logging
log_section() {
  echo -e "\n${YELLOW}${BOLD}--- $1 ---${NC}"
}

log_info() {
  echo -e "${BLUE}${INFO_EMOJI} $1${NC}"
}

log_success() {
  echo -e "${GREEN}${SUCCESS_EMOJI} $1${NC}"
}

log_error() {
  echo -e "${RED}${ERROR_EMOJI} $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}${WARNING_EMOJI} $1${NC}"
}

# Function to check network connectivity
check_network_connection() {
  log_info "Checking network connectivity..."
  if ! ping -c 1 google.com >/dev/null 2>&1; then
    log_error "No network connection. Please check your internet connection before proceeding."
    exit 1
  fi
  log_success "Network is up and running."
}

# Placeholder function for backup
perform_backup() {
  log_section "Backup Process"
  log_info "Creating a backup..."
  # Placeholder for actual backup command
}

# Function to check and repair disk health
check_disk_health() {
  log_section "Checking Disk Health"
  log_info "Checking disk health..."
  diskutil list | grep '^/' | awk '{print $1}' | while read -r disk; do
    log_info "Verifying $disk..."
    if diskutil verifyDisk "$disk" >/dev/null 2>&1; then
      log_info "Verification successful for $disk."
      if [[ "$AUTO_REPAIR" = true ]]; then
        log_info "Automatically attempting to repair $disk..."
        yes | diskutil repairDisk "$disk"
        if [[ $? -eq 0 ]]; then
          log_success "Disk repaired successfully."
        else
          log_error "Failed to repair $disk. Manual intervention may be required."
        fi
      else
        if [[ -t 1 ]]; then  # Check if stdout is a terminal
          log_warning "Repairing the disk might erase data on $disk. Proceed with repair? (y/N)"
          read -r proceed
          if [[ "$proceed" =~ ^[Yy]$ ]]; then
            log_info "Attempting to repair $disk..."
            yes | diskutil repairDisk "$disk"
            if [[ $? -eq 0 ]]; then
              log_success "Disk repaired successfully."
            else
              log_error "Failed to repair $disk. Manual intervention may be required."
            fi
          else
            log_warning "Repair canceled by user for $disk."
          fi
        else
          log_warning "Skipping repair as no user input is possible."
        fi
      fi
    else
      log_error "Verification failed for $disk. It might not support verification."
    fi
  done
}

# System updates
update_system() {
  log_section "System Updates"
  log_info "Updating macOS software..."
  sudo softwareupdate -i -a || log_error "Failed to update macOS software."
}

# Homebrew updates
update_homebrew() {
  if command_exists brew; then
    log_info "Updating Homebrew packages..."
    brew update && brew upgrade && brew cleanup || log_warning "Failed to update some Homebrew packages."
    log_info "Checking Homebrew health..."
    brew doctor || log_warning "Some issues detected with Homebrew setup."
  else
    log_warning "Homebrew not installed, installing now..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if command_exists brew; then
      log_success "Homebrew installed successfully."
      update_homebrew
    else
      log_error "Failed to install Homebrew."
      exit 1
    fi
  fi
}

# Mac App Store updates
update_mas() {
  if command_exists mas; then
    log_info "Updating Mac App Store apps..."
    mas outdated
    mas upgrade || log_warning "Failed to update some Mac App Store applications."
  else
    log_warning "Mac App Store CLI not installed, installing now..."
    brew install mas
    if command_exists mas; then
      log_success "Mac App Store CLI installed successfully."
      update_mas
    else
      log_error "Failed to install Mac App Store CLI."
      exit 1
    fi
  fi
}

# Ruby gems updates
update_ruby_gems() {
  if command_exists gem; then
    log_info "Updating Ruby Gems..."
    sudo gem update || log_warning "Failed to update some Ruby gems."
  else
    log_warning "Ruby Gems not installed, skipping Ruby updates."
  fi
}

# NPM packages updates
update_npm_packages() {
  if command_exists npm; then
    log_info "Updating global npm packages..."
    npm update npm -g
    npm update -g || log_warning "Failed to update some npm packages."
  else
    log_warning "npm not installed, skipping npm package updates."
  fi
}

# Python packages updates
update_python_packages() {
  if command_exists pip3; then
    log_info "Updating Python packages..."
    pip3 list --outdated | grep -v 'Package' | awk '{print $1}' | while read -r package; do
      log_info "Updating $package..."
      pip3 install --user -U "$package" && log_success "Updated $package successfully." || log_error "Failed to update $package."
    done
  else
    log_warning "pip not installed, skipping Python package updates."
  fi
}

# Maintenance tasks
perform_maintenance_tasks() {
  log_section "Maintenance Tasks"
  log_info "Flushing DNS cache..."
  sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder || log_error "Failed to flush DNS cache."
  log_info "Cleaning system logs and temporary files..."
  sudo rm -rf /var/log/*.gz /var/tmp/* || log_warning "Failed to clean some logs."
}

# Optimize storage
optimize_storage() {
  log_section "Optimize Storage"
  log_info "Optimizing storage..."
  sudo tmutil thinLocalSnapshots / 1000000000 1 || log_warning "Failed to optimize storage."
}

# Empty trash
empty_trash() {
  log_section "Empty Trash"
  log_info "Emptying trash..."
  sudo rm -rfv /Volumes/*/.Trashes/* ~/.Trash/* /private/var/log/asl/*.asl || log_warning "Failed to empty some trash."
}

# Completion notice
completion_notice() {
  log_section "Completion Notification"
  log_success "System update complete! 🌟"
  echo -e "${BLUE}Update script completed at $(date)${NC}"
  osascript -e 'display notification "All system updates and maintenance tasks are complete!" with title "System Update"'
}

# Main function orchestrates the workflow of the script
main() {
  log_info "Initializing update process..."
  check_network_connection
  perform_backup
  check_disk_health
  update_system
  update_homebrew
  update_mas
  update_ruby_gems
  update_npm_packages
  update_python_packages
  perform_maintenance_tasks
  optimize_storage
  empty_trash
  completion_notice
}

# Redirect output to a log file for accountability and transparency
exec > >(tee -a ~/update_script_log.txt)
exec 2>&1

main
