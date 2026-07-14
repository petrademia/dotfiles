#!/bin/bash
set -euo pipefail

echo "==> Applying macOS defaults"

# Close System Settings to prevent it from overriding your changes
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true

# Clear default dock icons
if command -v dockutil >/dev/null 2>&1; then
  echo "--> Clearing Dock icons via dockutil"
  dockutil --remove all >/dev/null 2>&1 || true
fi

# ==========================================
# Dock
# ==========================================
echo "--> Configuring Dock"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 128

# ==========================================
# Finder & Files
# ==========================================
echo "--> Configuring Finder"
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder CreateDesktop -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# New Finder windows open to Home
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

# Search the current folder by default (not "This Mac")
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Less nagging when renaming extensions
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Per-folder views live in .DS_Store and override FXPreferredViewStyle.
# Clear them under $HOME only (never system-wide) so list view actually sticks.
# Leave /Applications alone - icon view there is intentional/common.
echo "--> Clearing Finder per-folder view memory (~/.DS_Store under \$HOME)"
find "$HOME" -name .DS_Store -type f -delete 2>/dev/null || true
# Special locations (iCloud / Recents) keep separate icon-biased settings
defaults delete com.apple.finder ICloudViewSettings 2>/dev/null || true
defaults delete com.apple.finder SearchRecentsViewSettings 2>/dev/null || true

# ==========================================
# Save / Print dialogs & iCloud docs
# ==========================================
echo "--> Configuring save/print defaults"
# Save to disk (not iCloud) by default
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
# Expand save and print panels by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# ==========================================
# Menu Bar
# ==========================================
echo "--> Configuring Menu Bar"
# Auto-hide menu bar
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# Battery icon + percentage (Ventura+; percentage is per-host on modern macOS)
defaults write com.apple.controlcenter "NSStatusItem Visible Battery" -bool true
defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -bool true
defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true

# ==========================================
# Keyboard
# ==========================================
echo "--> Configuring Keyboard"
# Fast repeat rates
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10

# Disable smart quotes and dashes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# ==========================================
# Trackpad (Updated for Modern macOS)
# ==========================================
echo "--> Configuring Trackpad"
# Tap to click (Global + Bluetooth driver + Multitouch driver)
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

# Three-finger drag (Accessibility + Bluetooth driver + Multitouch driver)
defaults write com.apple.accessibility.TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

# ==========================================
# Screenshots
# ==========================================
echo "--> Configuring Screenshots"
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# ==========================================
# Reset & Apply
# ==========================================
echo "--> Restarting affected system services..."

# Flush the system preference caching daemon first
killall cfprefsd

# Restart UI elements
killall Dock
killall Finder

# Restart Control Center to pick up the battery percentage change
killall ControlCenter 2>/dev/null || true

echo "==> macOS defaults applied successfully!"
