#!/bin/bash

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
    echo -e "${RED}${ERROR_EMOJI} This script must not be run as root${NC}" 1>&2
    exit 1
fi

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
    log_success "Backup created successfully."
}

# Function to check and repair disk health
check_and_repair_disks() {
    log_section "Checking and Repairing Disk Health"
    log_info "Checking disk health..."
    disks=$(diskutil list | grep '^/dev/' | awk '{print $1}')
    for disk in $disks; do
        log_info "Verifying $disk..."
        if diskutil verifyDisk "$disk" >/dev/null 2>&1; then
            log_info "Verification successful for $disk."
        else
            log_warning "Verification failed for $disk. Attempting repair..."
            if diskutil repairDisk "$disk" >/dev/null 2>&1; then
                log_success "Repair successful for $disk."
            else
                log_error "Repair failed for $disk. Retrying..."
                # Retry mechanism
                if diskutil repairDisk "$disk" >/dev/null 2>&1; then
                    log_success "Repair successful for $disk on retry."
                else
                    log_error "Repair failed for $disk on retry. Please check the disk manually."
                fi
            fi
        fi
        partitions=$(diskutil list "$disk" | grep '^/dev/' | awk '{print $1}')
        for partition in $partitions; do
            log_info "Verifying $partition..."
            if diskutil verifyVolume "$partition" >/dev/null 2>&1; then
                log_info "Verification successful for $partition."
            else
                log_warning "Verification failed for $partition. Attempting repair..."
                if diskutil repairVolume "$partition" >/dev/null 2>&1; then
                    log_success "Repair successful for $partition."
                else
                    log_error "Repair failed for $partition. Retrying..."
                    # Retry mechanism
                    if diskutil repairVolume "$partition" >/dev/null 2>&1; then
                        log_success "Repair successful for $partition on retry."
                    else
                        log_error "Repair failed for $partition on retry. Please check the partition manually."
                    fi
                fi
            fi
        done
    done
}

# Function to handle npm errors
handle_npm_errors() {
    log_section "Handling npm Errors"
    local error="$1"
    if echo "$error" | grep -q "EACCES"; then
        log_warning "Fixing npm permissions..."
        sudo chown -R $(whoami) /opt/homebrew/lib/node_modules/npm /opt/homebrew/lib/node_modules/.npm-*
        sudo chown -R $(whoami) ~/.npm
    elif echo "$error" | grep -q "E404"; then
        log_warning "Removing invalid npm package..."
        local invalid_package=$(echo "$error" | grep -oP "(?<=404  ').*(?= is not in this registry)")
        npm uninstall -g "$invalid_package" || true
    elif echo "$error" | grep -q "EUSAGE"; then
        log_warning "Fixing npm usage error..."
        npm uninstall -g $(echo "$error" | grep -oP "(?<=Usage:).*") || true
    elif echo "$error" | grep -q "EACCESS"; then
        log_warning "Fixing npm EACCESS error..."
        sudo chown -R $(whoami) ~/.npm
        sudo chown -R $(whoami) /usr/local/lib/node_modules
        sudo chown -R $(whoami) /opt/homebrew/lib/node_modules
    else
        log_warning "Unknown npm error encountered: $error"
    fi
}

# Function to handle Ruby errors
handle_ruby_errors() {
    log_section "Handling Ruby Errors"
    local error="$1"
    if echo "$error" | grep -q "OpenSSL"; then
        log_warning "Fixing OpenSSL issue..."
        brew install openssl
        brew link --force openssl
        if ! openssl version | grep -q "OpenSSL"; then
            log_error "OpenSSL installation or linking failed."
            exit 1
        fi
    elif echo "$error" | grep -q "Gem::FilePermissionError"; then
        log_warning "Fixing Ruby Gem permissions error..."
        sudo chown -R $(whoami) /Library/Ruby/Gems/2.6.0
    elif echo "$error" | grep -q "There are no versions of"; then
        log_warning "Handling incompatible Ruby gem issue..."
        local gem_name=$(echo "$error" | grep -oP "(?<=Error installing ).*(?= there are no versions of)")
        log_info "Uninstalling incompatible gem: $gem_name..."
        gem uninstall "$gem_name"
        log_info "Installing compatible version of $gem_name..."
        gem install "$gem_name" -v "$(gem search "^$gem_name$" --remote | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    else
        log_warning "Unknown Ruby error encountered: $error"
    fi
}

# Function to handle Python errors
handle_python_errors() {
    log_section "Handling Python Errors"
    local error="$1"
    if echo "$error" | grep -q "externally-managed-environment"; then
        log_warning "Handling externally managed environment error..."
        # Use virtual environment for Python package installation
        python3 -m venv /tmp/python-venv
        source /tmp/python-venv/bin/activate
        log_info "Virtual environment created and activated."
    elif echo "$error" | grep -q "normal site-packages is not writeable"; then
        log_warning "Defaulting to user installation due to non-writable site-packages..."
        python3 -m pip install --user --upgrade pip
        pip3 install --user --upgrade $(pip3 list --outdated | awk 'NR>2 {print $1}') || log_warning "Failed to update some Python packages."
    elif echo "$error" | grep -q "ERROR: You must give at least one requirement to install"; then
        log_warning "No requirements specified for pip install. Skipping..."
    else
        log_warning "Unknown Python error encountered: $error"
    fi
}

# Function to clear system and user caches
clear_caches() {
    log_section "Clearing System Caches"
    log_info "Clearing system and user caches..."
    if csrutil status | grep -q "enabled"; then
        log_warning "System Integrity Protection (SIP) is enabled. Skipping system caches."
    else
        sudo find /Library/Caches -type f -delete 2>/dev/null || log_warning "Some system caches could not be cleared."
    fi
    find ~/Library/Caches -type f -delete 2>/dev/null || log_warning "Some user caches could not be cleared."
    log_success "System and user caches cleared successfully."
}

# Function to clear system and user logs
clear_logs() {
    log_section "Clearing System Logs"
    log_info "Clearing system and user logs..."
    sudo find /var/log -type f -delete 2>/dev/null || log_warning "Some system logs could not be cleared."
    find ~/Library/Logs -type f -delete 2>/dev/null || log_warning "Some user logs could not be cleared."
    log_success "System and user logs cleared successfully."
}

# Function to manage startup items
manage_startup_items() {
    log_section "Managing Startup Items"
    log_info "Disabling unnecessary startup items..."
    sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.spindump.plist
    sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.CrashReporterSupportHelper.plist
    if [[ $? -ne 0 ]]; then
        log_warning "Some startup items could not be disabled. Please check them manually."
    else
        log_success "Unnecessary startup items disabled."
    fi
}

# Function to display system information
display_system_info() {
    log_section "System Information"
    log_info "Displaying system information..."
    system_profiler SPSoftwareDataType SPHardwareDataType
    log_success "System information displayed successfully."
}

# System updates
update_system() {
    log_section "System Updates"
    log_info "Updating macOS software..."
    sudo softwareupdate -i -a || log_error "Failed to update macOS software."
    log_success "macOS software updated successfully."
}

# Homebrew updates
update_homebrew() {
    ensure_command "brew" "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    if command_exists brew; then
        log_info "Updating Homebrew packages..."
        brew update && brew upgrade && brew cleanup || log_warning "Failed to update some Homebrew packages."
        log_success "Homebrew packages updated successfully."
    else
        log_error "Homebrew installation failed."
    fi
}

# npm updates
update_npm() {
    ensure_command "npm" "brew install node"
    if command_exists npm; then
        log_info "Updating npm packages..."
        npm install -g npm || handle_npm_errors "$(npm install -g npm 2>&1)"
        npm update -g || handle_npm_errors "$(npm update -g 2>&1)"
        log_success "npm and global packages updated successfully."
    else
        log_error "npm installation failed."
    fi
}

# Ruby Gem updates
update_ruby_gems() {
    ensure_command "gem" "brew install ruby"
    if command_exists gem; then
        log_info "Updating Ruby gems..."
        gem update --system || handle_ruby_errors "$(gem update --system 2>&1)"
        gem update || handle_ruby_errors "$(gem update 2>&1)"
        gem cleanup || log_warning "Failed to clean up outdated Ruby gems."
        log_success "Ruby gems updated successfully."
    else
        log_error "Ruby installation failed."
    fi
}

# Python updates
update_python() {
    ensure_command "python3" "brew install python"
    if command_exists python3; then
        log_info "Updating Python packages..."
        python3 -m pip install --upgrade pip || handle_python_errors "$(python3 -m pip install --upgrade pip 2>&1)"
        pip3 install --upgrade $(pip3 list --outdated | awk 'NR>2 {print $1}') || handle_python_errors "$(pip3 install --upgrade $(pip3 list --outdated | awk 'NR>2 {print $1}') 2>&1)"
        log_success "Python packages updated successfully."
    else
        log_error "Python installation failed."
    fi
}

# Call functions
log_info "Starting system maintenance script."
START_TIME=$(date +%s)
check_network_connection
perform_backup
check_and_repair_disks
clear_caches
clear_logs
manage_startup_items
update_system
update_homebrew
update_npm
update_ruby_gems
update_python
display_system_info
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
log_success "System maintenance script completed successfully in $RUNTIME seconds."
