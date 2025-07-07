#!/bin/bash

# Test script for README auto-update functionality
# This script validates the setup and runs a test update

set -e

echo "🧪 Testing README Auto-Update Setup"
echo "=================================="

# Check if required files exist
echo "📋 Checking required files..."

if [ ! -f "README.md" ]; then
    echo "❌ README.md not found!"
    exit 1
fi
echo "✅ README.md found"

if [ ! -f "scripts/update-contributions.sh" ]; then
    echo "❌ Update script not found!"
    exit 1
fi
echo "✅ Update script found"

if [ ! -f ".github/workflows/update-readme.yml" ]; then
    echo "❌ GitHub Actions workflow not found!"
    exit 1
fi
echo "✅ GitHub Actions workflow found"

# Check if required tools are available
echo -e "\n🔧 Checking required tools..."

if ! command -v curl &> /dev/null; then
    echo "❌ curl not found!"
    exit 1
fi
echo "✅ curl available"

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found! Installing..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo "❌ Cannot install jq automatically. Please install it manually."
        exit 1
    fi
fi
echo "✅ jq available"

if ! command -v python3 &> /dev/null; then
    echo "❌ python3 not found!"
    exit 1
fi
echo "✅ python3 available"

# Make script executable
chmod +x scripts/update-contributions.sh
echo "✅ Made update script executable"

# Test GitHub API connection
echo -e "\n🌐 Testing GitHub API connection..."
if curl -s "https://api.github.com/users/yunus25jmi1" | jq -r '.login' &> /dev/null; then
    echo "✅ GitHub API connection successful"
else
    echo "❌ GitHub API connection failed!"
    exit 1
fi

# Create a backup before testing
echo -e "\n💾 Creating backup..."
cp README.md README.md.test-backup
echo "✅ Backup created: README.md.test-backup"

# Run the update script in test mode
echo -e "\n🚀 Running update script test..."
if ./scripts/update-contributions.sh; then
    echo "✅ Update script executed successfully"
    
    # Check if file was modified
    if [ -f "README.md.backup" ]; then
        if ! diff -q README.md README.md.backup &> /dev/null; then
            echo "✅ README.md was updated with new content"
        else
            echo "ℹ️ No changes were made (this is normal if no recent activity)"
        fi
    fi
else
    echo "❌ Update script failed!"
    # Restore from backup
    if [ -f "README.md.test-backup" ]; then
        cp README.md.test-backup README.md
        echo "✅ Restored README.md from backup"
    fi
    exit 1
fi

# Show validation results
echo -e "\n📊 Validation Results:"
echo "====================="

# Check if GitHub Actions workflow is valid
echo "🔍 Validating GitHub Actions workflow..."
if grep -q "update-readme" .github/workflows/update-readme.yml; then
    echo "✅ Workflow file contains expected job"
else
    echo "❌ Workflow file may be invalid"
fi

# Check if script has proper permissions
if [ -x "scripts/update-contributions.sh" ]; then
    echo "✅ Update script has execute permissions"
else
    echo "❌ Update script lacks execute permissions"
fi

# Cleanup
if [ -f "README.md.backup" ]; then
    rm README.md.backup
    echo "✅ Cleaned up temporary backup"
fi

echo -e "\n🎉 Setup validation completed successfully!"
echo -e "\n📝 Next steps:"
echo "1. Commit and push the new files to your repository"
echo "2. The GitHub Action will run automatically on schedule"
echo "3. You can also trigger it manually from the Actions tab"
echo -e "\n🔗 Monitor your workflow at: https://github.com/yunus25jmi1/yunus25jmi1/actions"

# Restore original state
if [ -f "README.md.test-backup" ]; then
    if ! diff -q README.md README.md.test-backup &> /dev/null; then
        echo -e "\n❓ The test made changes to your README.md"
        echo "Would you like to keep the changes? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            cp README.md.test-backup README.md
            echo "✅ Restored original README.md"
        else
            echo "✅ Keeping updated README.md"
        fi
    fi
    rm README.md.test-backup
fi

echo -e "\n✨ Test completed!"
