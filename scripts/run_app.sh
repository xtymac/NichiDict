#!/bin/bash
# Quick launch script for NichiDict app

set -e

echo "🚀 NichiDict Quick Launch"
echo "========================="

# Navigate to project
cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

echo "📂 Project: $PROJECT_DIR"

# Check if simulator is running
SIMULATOR_STATUS=$(xcrun simctl list devices | grep "iPhone 17 Pro" | grep "Booted" || echo "")

if [ -z "$SIMULATOR_STATUS" ]; then
    echo "📱 Starting iPhone 17 Pro simulator..."
    xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || echo "Simulator already booting..."
    open -a Simulator
    sleep 3
else
    echo "✅ Simulator already running"
fi

# Build the app
echo "🔨 Building NichiDict..."
cd NichiDict
xcodebuild -scheme NichiDict \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -quiet \
    build

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded"
else
    echo "❌ Build failed"
    exit 1
fi

# Install and launch
echo "📲 Installing app..."
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/NichiDict-alttqmwmehovdldfmqiqlgmqtvjf/Build/Products/Debug-iphonesimulator/NichiDict.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at: $APP_PATH"
    echo "   Looking for DerivedData folder..."
    APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "NichiDict.app" -path "*/Debug-iphonesimulator/*" | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find NichiDict.app"
        exit 1
    fi
    echo "✅ Found app at: $APP_PATH"
fi

xcrun simctl install booted "$APP_PATH"

echo "🚀 Launching NichiDict..."
xcrun simctl launch booted org.uixai.NichiDict

echo ""
echo "✅ NichiDict is now running!"
echo ""
echo "📋 Quick Tips:"
echo "   • Try searching: 食べる, 勉強, 日本"
echo "   • Search works with: Kanji, Hiragana, Romaji"
echo "   • Tap any result to see full details"
echo ""
echo "🐛 To view logs:"
echo "   xcrun simctl spawn booted log stream --predicate 'subsystem contains \"NichiDict\"'"
echo ""
