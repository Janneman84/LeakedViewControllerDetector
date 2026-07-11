#!/bin/bash

# Format Swift code using SwiftFormat by Nick Lockwood
# This script can be run locally to format code before committing

set -e

echo "🔧 Formatting Swift code with SwiftFormat..."

# Check if SwiftFormat is installed
if ! command -v swiftformat &> /dev/null; then
    echo "❌ SwiftFormat is not installed."
    echo "Install it with: brew install swiftformat"
    echo "Or build from source: https://github.com/nicklockwood/SwiftFormat"
    exit 1
fi

# Check current formatting status
echo "📋 Checking current formatting status..."
if swiftformat --dryrun Sources/ Tests/ > /dev/null 2>&1; then
    echo "✨ Code is already properly formatted!"
else
    echo "📝 Formatting issues found. Applying fixes..."
    
    # Format all Swift files in Sources and Tests
    echo "📁 Formatting Sources/..."
    swiftformat Sources/
    
    echo "📁 Formatting Tests/..."
    swiftformat Tests/
    
    echo "✅ Swift code formatting completed!"
    
    # Check if there are any changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "📝 Files were formatted. Please review the changes:"
        git status --short
        echo ""
        echo "💡 You can see the diff with: git diff"
    else
        echo "✨ No changes were needed after all."
    fi
fi 