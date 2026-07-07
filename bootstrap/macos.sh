#!/bin/bash
set -euo pipefail

echo "==> Applying macOS defaults"

# Dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 128
killall Dock

# Finder
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder CreateDesktop -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
killall Finder

# Menu bar - auto hide
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# Keyboard - faster repeat
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10

# Trackpad - tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

# Three-finger drag
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

# Disable smart quotes and dashes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Screenshot location
defaults write com.apple.screencapture location ~/Screenshots
mkdir -p ~/Screenshots

# Battery percentage
defaults write com.apple.menuextra.battery ShowPercent -bool true

echo "==> macOS defaults applied. Restart apps to see changes."
