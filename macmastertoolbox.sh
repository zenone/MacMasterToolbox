#!/bin/bash

# Mac Update and Maintenance Script

# Colors and Styles
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function Definitions
command_exists() {
    type "$1" &> /dev/null
}

log_section() {
    echo -e "\n${YELLOW}${BOLD}--- $1 ---${NC}"
}

log_info() {
    echo -e "${YELLOW}[*] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[*] $1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

perform_backup() {
    log_section "Backup Process"
    log_info "Creating a backup..."
    # rsync -avh --exclude '.Trash' ~/Documents/ ~/Backups/DocumentsBackup_$(date +"%Y%m%d")/
}

check_disk_health() {
    log_section "Disk Space and Health"
    log_info "Checking available disk space..."
    df -H
    log_info "Checking disk health..."
    for disk in $(diskutil list | grep '^/' | awk '{print $1}'); do
        log_info "Checking $disk..."
        if ! sudo diskutil verifyDisk $disk; then
            log_error "Error verifying $disk. This disk might not support verification."
        fi
        for volume in $(diskutil list $disk | grep 'Apple_APFS' | awk '{print $NF}'); do
            log_info "Checking volume $volume..."
            if ! sudo diskutil verifyVolume $volume; then
                log_error "Error verifying volume $volume. This volume might not support verification or might be a special volume."
            fi
        done
    done
}

system_checks() {
    log_section "System Checks"
    log_info "Checking System Integrity Protection status..."
    csrutil status
    log_info "Testing network connectivity..."
    if ! ping -c 4 google.com; then
        log_error "Network issue detected. Exiting."
        exit 1
    fi
}

update_software() {
    log_section "Software Updates"
    log_info "Updating macOS software..."
    sudo softwareupdate -i -a
}

update_homebrew() {
    if command_exists brew; then
        log_info "Updating Homebrew packages..."
        brew update
        brew upgrade
        brew cleanup -s
        brew upgrade --cask
        log_info "Running Homebrew diagnostics..."
        if ! brew doctor; then
            log_error "Homebrew diagnostics reported issues."
        fi
        brew missing
    else
        log_error "Homebrew not installed, skipping Homebrew updates."
    fi
}

update_mas() {
    if command_exists mas; then
        log_info "Updating Mac App Store apps..."
        mas outdated
        mas upgrade
    else
        log_error "Mac App Store CLI not installed, skipping App Store updates."
    fi
}

update_ruby_gems() {
    if command_exists gem; then
        log_info "Updating Ruby Gems..."
        sudo gem update
    else
        log_error "Ruby Gems not installed, skipping Ruby updates."
    fi
}

update_npm_packages() {
    if command_exists npm; then
        log_info "Updating global npm packages..."
        npm update npm -g
        npm update -g
    else
        log_error "npm not installed, skipping npm package updates."
    fi
}

update_python_packages() {
    if command_exists pip; then
        log_info "Updating Python packages..."
        pip list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n 1 pip install --user -U
    else
        log_error "pip not installed, skipping Python package updates."
    fi
}

perform_maintenance_tasks() {
    log_section "Maintenance Tasks"
    log_info "Flushing DNS cache..."
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
    log_info "Cleaning up unused packages..."
    if command_exists brew; then
        brew cleanup
    fi
    if command_exists npm; then
        npm cache clean --force
    fi
    log_info "Cleaning up old system logs..."
    sudo rm -rf /var/log/*.gz
}

optimize_storage() {
    log_section "Time Machine and Storage"
    log_info "Checking the status of Time Machine backups..."
    tmutil latestbackup
    log_info "Optimizing storage..."
    sudo tmutil thinLocalSnapshots / 1000000000 1
}

empty_trash() {
    log_section "Trash Cleanup"
    log_info "Emptying trash..."
    sudo rm -rfv /Volumes/*/.Trashes/*; sudo rm -rfv ~/.Trash/*; sudo rm -rfv /private/var/log/asl/*.asl
}

notify_completion() {
    log_success "System update complete!"
    echo -e "${BLUE}Update script completed at $(date)${NC}"
    osascript -e 'display notification "System update complete!" with title "Update Script"'
}

show_reminders() {
    echo -e "\n${RED}${BOLD}[!] Don't forget to manually check for deprecated packages and monitor system performance!${NC}"
    echo -e "${RED}[!] Consider rebooting your system if major updates were installed.${NC}"
}

# Redirect output to a log file with timestamp
exec > >(tee -a ~/update_script_log.txt)
exec 2>&1
echo -e "${BLUE}${BOLD}Update script started at $(date)${NC}"

# Perform all tasks
perform_backup
check_disk_health
system_checks
update_software
update_homebrew
update_mas
update_ruby_gems
update_npm_packages
update_python_packages
perform_maintenance_tasks
optimize_storage
empty_trash
notify_completion
show_reminders
