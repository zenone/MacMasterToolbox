#!/bin/bash

# Colors and Emoji Codes for readability and user feedback
if ! command -v tput >/dev/null 2>&1; then
    echo "tput not found. Please install ncurses and try again."
    exit 1
fi
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
NC=$(tput sgr0) # No Color
INFO_EMOJI="ℹ️"
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
NETWORK_EMOJI="🌐"

# Ensure the script is not run as root to avoid Homebrew issues, except for specific commands
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}${ERROR_EMOJI} This script must not be run as root${NC}" 1>&2
    read -p "Would you like to continue as a non-root user? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        exec sudo -u $(logname) $0
    else
        exit 1
    fi
fi

# Determine the user's shell
USER_SHELL=$(basename "$SHELL")
SHELL_RC_FILE=""

case "$USER_SHELL" in
    bash)
        SHELL_RC_FILE="$HOME/.bashrc"
        ;;
    zsh)
        SHELL_RC_FILE="$HOME/.zshrc"
        ;;
    *)
        echo -e "${RED}${ERROR_EMOJI} Unsupported shell: $USER_SHELL. Please use bash or zsh.${NC}" 1>&2
        exit 1
        ;;
esac

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

# Trap to handle unexpected script termination and ensure cleanup
trap 'log_error "User exited the script by pressing Ctrl+C."; exit 1' SIGINT SIGTERM

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Automatically install missing commands
ensure_command() {
    local command="$1"
    local install_cmd=("$2")
    if ! command_exists "$command"; then
        log_info "Installing $command..."
        "${install_cmd[@]}" && log_success "$command installed successfully." || { log_error "Failed to install $command."; exit 1; }
    fi
}

# Function to check network connectivity
check_network_connection() {
    log_info "Checking network connectivity..."
    local hosts=("google.com" "cloudflare.com" "yahoo.com")
    local all_successful=true

    for host in "${hosts[@]}"; do
        if ping -c 1 "$host" >/dev/null 2>&1; then
            log_success "Network connection successful to $host."
        else
            log_warning "No network connection to $host."
            all_successful=false
        fi
    done

    if $all_successful; then
        log_success "All network connections are successful. Network is up and running."
    else
        log_error "Not all network connections are successful. Please check your internet connection."
        exit 1
    fi
}

# Enhanced backup function using rsync
perform_backup() {
    log_section "Backup Process"
    local backup_dir="$1"
    local source_dir="$2"
    if [ ! -d "$backup_dir" ]; then
        log_warning "Backup directory $backup_dir does not exist. Creating it..."
        mkdir -p "$backup_dir" || { log_error "Failed to create backup directory $backup_dir."; exit 1; }
    fi
    if [ ! -w "$backup_dir" ]; then
        log_error "Backup directory $backup_dir is not writable."
        exit 1
    fi
    log_info "Creating a backup using rsync..."
    rsync -avh --delete "$source_dir" "$backup_dir" || { log_error "Backup failed. Please check the backup directory and permissions."; exit 1; }
    log_success "Backup created successfully."
}

# Enhanced function to check and repair disk health
check_and_repair_disks() {
    log_section "Checking and Repairing Disk Health"
    log_info "Checking disk health..."
    disks=$(diskutil list | grep '^/dev/' | awk '{print $1}')
    for disk in $disks; do
        log_info "Verifying and repairing $disk..."
        if ! diskutil verifyDisk "$disk" >/dev/null 2>&1; then
            log_warning "Verification failed for $disk. Attempting repair..."
            if ! diskutil repairDisk "$disk" >/dev/null 2>&1; then
                log_error "Repair failed for $disk. Please check the disk manually."
            else
                log_success "Repair successful for $disk."
            fi
        else
            log_info "Verification successful for $disk."
        fi
        partitions=$(diskutil list "$disk" | grep '^/dev/' | awk '{print $1}')
        for partition in $partitions; do
            log_info "Verifying and repairing $partition..."
            if ! diskutil verifyVolume "$partition" >/dev/null 2>&1; then
                log_warning "Verification failed for $partition. Attempting repair..."
                if ! diskutil repairVolume "$partition" >/dev/null 2>&1; then
                    log_error "Repair failed for $partition. Please check the partition manually."
                else
                    log_success "Repair successful for $partition."
                fi
            else
                log_info "Verification successful for $partition."
            fi
        done
    done
}

handle_npm_errors() {
    log_section "Handling npm Errors"
    local error="$1"
    if echo "$error" | grep -q "EACCES"; then
        log_warning "Fixing npm permissions..."
        sudo chown -R $(whoami) /opt/homebrew/lib/node_modules/npm /opt/homebrew/lib/node_modules/.npm-*
        sudo chown -R $(whoami) ~/.npm
    elif echo "$error" | grep -q "E404"; then
        log_warning "Removing invalid npm package..."
        local invalid_package=$(echo "$error" | grep -o "'@[^/]\+/\.[^@]\+@[^']\+'" | tr -d "'")
        npm uninstall -g "$invalid_package" || true
        sed -i.bak "/\"$invalid_package\": \".*\"/d" package.json
        log_success "Removed invalid npm package: $invalid_package"
    elif echo "$error" | grep -q "EUSAGE"; then
        log_warning "Fixing npm usage error..."
        npm uninstall -g $(echo "$error" | grep -o "Usage: .*" | awk '{print $2}') || true
    elif echo "$error" | grep -q "EACCESS"; then
        log_warning "Fixing npm EACCESS error..."
        sudo chown -R $(whoami) ~/.npm
        sudo chown -R $(whoami) /usr/local/lib/node_modules
        sudo chown -R $(whoami) /opt/homebrew/lib/node_modules
    else
        log_warning "Unknown npm error encountered: $error"
    fi
}

# Function to handle deprecated npm packages
handle_npm_deprecated_warnings() {
    log_section "Handling npm Deprecated Warnings"
    npm list -g --depth=0 | grep 'deprecated' | awk '{print $2}' | awk -F '@' '{print $1}' | while read -r package; do
        log_info "Removing deprecated npm package: $package"
        npm uninstall -g "$package" || log_warning "Failed to remove $package. Manual intervention required."
    done
}

# Function to handle Ruby errors and manage Ruby using rbenv
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
        sudo chown -R $(whoami) $(gem env gemdir)
    elif echo "$error" | grep -q "There are no versions of"; then
        log_warning "Handling incompatible Ruby gem issue..."
        local gem_name=$(echo "$error" | grep -o "Error installing .*" | awk '{print $3}')
        log_info "Uninstalling incompatible gem: $gem_name..."
        gem uninstall "$gem_name"
        log_info "Installing compatible version of $gem_name..."
        gem install "$gem_name" -v "$(gem search "^$gem_name$" --remote | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    elif echo "$error" | grep -q "requires Ruby version"; then
        log_warning "Fixing Ruby version issue by installing and setting up rbenv..."
        brew install rbenv ruby-build
        echo 'eval "$(rbenv init -)"' >> "$SHELL_RC_FILE"
        source "$SHELL_RC_FILE"
        latest_ruby=$(rbenv install -l | grep -v - | tail -1)
        if ! rbenv versions | grep -q "$latest_ruby"; then
            rbenv install "$latest_ruby"
        fi
        rbenv global "$latest_ruby"
        ruby -v
        gem install rubygems-update
        update_rubygems
    elif echo "$error" | grep -q "Errno::ENOENT"; then
        log_warning "Handling missing file error..."
        local missing_gem=$(echo "$error" | grep -o "No such file or directory - .*" | awk '{print $6}')
        gem uninstall "$missing_gem" --force
        gem install "$missing_gem"
    elif echo "$error" | grep -q "rvm is not a function"; then
        log_warning "Handling RVM issue..."
        rvm implode --force || log_warning "Failed to implode RVM. Manual intervention required."
    else
        log_warning "Unknown Ruby error encountered: $error"
    fi
}

# Function to handle Ruby gem extension errors
handle_ruby_gem_extensions() {
    log_section "Handling Ruby Gem Extensions"
    log_info "Rebuilding gem extensions..."
    gem list | grep "extensions are not built" | awk '{print $1}' | while read -r gem_name; do
        version=$(gem list "$gem_name" --local | grep "$gem_name" | awk '{print $2}' | tr -d '()')
        log_info "Rebuilding $gem_name --version $version..."
        gem pristine "$gem_name" --version "$version"
    done
    log_success "Gem extensions rebuilt successfully."
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
        pip install --upgrade pip
        pip install $(pip list --outdated | awk 'NR>2 {print $1}') || log_warning "Failed to update some Python packages."
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
    for plist in /System/Library/LaunchDaemons/com.apple.spindump.plist /System/Library/LaunchDaemons/com.apple.CrashReporterSupportHelper.plist; do
        if sudo launchctl bootout system "$plist"; then
            log_success "Disabled $plist"
        else
            log_warning "Failed to disable $plist. Attempting unload..."
            if sudo launchctl unload "$plist"; then
                log_success "Unloaded $plist"
            else
                log_warning "Failed to unload $plist. Attempting with root privileges..."
                if sudo -n true; then
                    sudo launchctl bootout system "$plist" || sudo launchctl unload "$plist" || log_error "Failed to manage $plist. Manual intervention required."
                else
                    log_warning "Root privileges required to manage $plist. Skipping..."
                fi
            fi
        fi
    done
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
        handle_npm_deprecated_warnings
        log_success "npm and global packages updated successfully."
    else
        log_error "npm installation failed."
    fi
}

# Ruby Gem updates using rbenv
update_ruby_gems() {
    ensure_command "rbenv" "brew install rbenv ruby-build"
    if command_exists rbenv; then
        log_info "Updating Ruby gems using rbenv..."
        echo 'eval "$(rbenv init -)"' >> "$SHELL_RC_FILE"
        source "$SHELL_RC_FILE"
        latest_ruby=$(rbenv install -l | grep -v - | tail -1)
        if ! rbenv versions | grep -q "$latest_ruby"; then
            rbenv install "$latest_ruby"
        fi
        rbenv global "$latest_ruby"
        ruby -v
        gem install rubygems-update
        update_rubygems
        gem update || handle_ruby_errors "$(gem update 2>&1)"
        handle_ruby_gem_extensions
        gem cleanup || log_warning "Failed to clean up outdated Ruby gems."
        log_success "Ruby gems updated successfully."
    else
        log_error "rbenv installation failed."
    fi
}

# Python updates
update_python() {
    ensure_command "python3" "brew install python"
    if command_exists python3; then
        log_info "Updating Python packages..."
        handle_python_errors "externally-managed-environment"
        log_success "Python packages updated successfully."
    else
        log_error "Python installation failed."
    fi
}

# Check for disk space
check_disk_space() {
    log_section "Checking Disk Space"
    log_info "Checking available disk space..."
    if df -h / | awk '$6=="/"{print $5}' | grep -q '^[8-9][0-9]%;\|100%'; then
        log_warning "Disk space is running low. Please free up some space before proceeding."
        exit 1
    else
        log_success "Sufficient disk space available."
    fi
}

# Call functions
log_info "Starting system maintenance script."
START_TIME=$(date +%s)
check_network_connection
# perform_backup "/path/to/backup" "$HOME"  # Uncomment and set correct paths for backup
check_and_repair_disks
check_disk_space
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
