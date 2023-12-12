#!/bin/bash

# Colors and Styles
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Exit immediately if a command exits with a non-zero status
# set -e

# Redirect output to a log file with timestamp
exec > >(tee -a ~/update_script_log.txt)
exec 2>&1
echo -e "${BLUE}${BOLD}Update script started at $(date)${NC}"

# Function to check command availability
command_exists() {
    type "$1" &> /dev/null
}

# Backup command
echo -e "\n${YELLOW}${BOLD}--- Backup Process ---${NC}"
echo -e "${YELLOW}[*] Creating a backup...${NC}"
# rsync -avh --exclude '.Trash' ~/Documents/ ~/Backups/DocumentsBackup_$(date +"%Y%m%d")/

# Disk Space and Health
echo -e "\n${YELLOW}${BOLD}--- Disk Space and Health ---${NC}"
echo -e "${YELLOW}[*] Checking available disk space...${NC}"
df -H

# Dynamically checking disk health
echo -e "${YELLOW}[*] Checking disk health...${NC}"
for disk in $(diskutil list | grep '^/' | awk '{print $1}'); do
    echo -e "${YELLOW}Checking $disk...${NC}"
    sudo diskutil verifyDisk $disk

    for volume in $(diskutil list $disk | grep 'Apple_APFS' | awk '{print $NF}'); do
        echo -e "${YELLOW}Checking volume $volume...${NC}"
        sudo diskutil verifyVolume $volume
    done
done

# System Checks
echo -e "\n${YELLOW}${BOLD}--- System Checks ---${NC}"
echo -e "${YELLOW}[*] Checking System Integrity Protection status...${NC}"
csrutil status
echo -e "${YELLOW}[*] Testing network connectivity...${NC}"
ping -c 4 google.com || { echo -e "${RED}Network issue detected. Exiting.${NC}"; exit 1; }

# Software Updates
echo -e "\n${YELLOW}${BOLD}--- Software Updates ---${NC}"
echo -e "${YELLOW}[*] Updating macOS software...${NC}"
sudo softwareupdate -i -a

# Homebrew
if command_exists brew; then
    echo -e "${YELLOW}[*] Updating Homebrew packages...${NC}"
    brew update
    brew upgrade
    brew cleanup -s
    brew upgrade --cask
    echo -e "${YELLOW}[*] Running Homebrew diagnostics...${NC}"
    brew doctor
    brew missing
else
    echo -e "${RED}Homebrew not installed, skipping Homebrew updates.${NC}"
fi

# Mac App Store
if command_exists mas; then
    echo -e "${YELLOW}[*] Updating Mac App Store apps...${NC}"
    mas outdated
    mas upgrade
else
    echo -e "${RED}Mac App Store CLI not installed, skipping App Store updates.${NC}"
fi

# Ruby Gems
if command_exists gem; then
    echo -e "${YELLOW}[*] Updating Ruby Gems...${NC}"
    sudo gem update
else
    echo -e "${RED}Ruby Gems not installed, skipping Ruby updates.${NC}"
fi

# NPM Packages
if command_exists npm; then
    echo -e "${YELLOW}[*] Updating global npm packages...${NC}"
    npm update npm -g
    npm update -g
else
    echo -e "${RED}npm not installed, skipping npm package updates.${NC}"
fi

# Python Packages
if command_exists pip; then
    echo -e "${YELLOW}[*] Updating Python packages...${NC}"
    pip list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n 1 pip install --user -U
else
    echo -e "${RED}pip not installed, skipping Python package updates.${NC}"
fi

# Maintenance Tasks
echo -e "\n${YELLOW}${BOLD}--- Maintenance Tasks ---${NC}"
echo -e "${YELLOW}[*] Flushing DNS cache...${NC}"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
echo -e "${YELLOW}[*] Cleaning up unused packages...${NC}"
brew cleanup
npm cache clean --force
echo -e "${YELLOW}[*] Cleaning up old system logs...${NC}"
sudo rm -rf /var/log/*.gz

# Time Machine and Storage
echo -e "\n${YELLOW}${BOLD}--- Time Machine and Storage ---${NC}"
echo -e "${YELLOW}[*] Checking the status of Time Machine backups...${NC}"
tmutil latestbackup
echo -e "${YELLOW}[*] Optimizing storage...${NC}"
sudo tmutil thinLocalSnapshots / 1000000000 1

# Trash Cleanup
echo -e "\n${YELLOW}${BOLD}--- Trash Cleanup ---${NC}"
echo -e "${YELLOW}[*] Emptying trash...${NC}"
sudo rm -rfv /Volumes/*/.Trashes/*; sudo rm -rfv ~/.Trash/*; sudo rm -rfv /private/var/log/asl/*.asl

# Completion Notification
echo -e "\n${GREEN}${BOLD}[*] System update complete!${NC}"
echo -e "${BLUE}Update script completed at $(date)${NC}"
osascript -e 'display notification "System update complete!" with title "Update Script"'

# Reminder
echo -e "\n${RED}${BOLD}[!] Don't forget to manually check for deprecated packages and monitor system performance!${NC}"
echo -e "${RED}[!] Consider rebooting your system if major updates were installed.${NC}"
