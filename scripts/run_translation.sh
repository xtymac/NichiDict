#!/bin/bash

# Convenience script to run AI translation
# This automatically activates the virtual environment

cd "$(dirname "$0")/.."

# Check if API key is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY not set"
    echo ""
    echo "Please set your API key:"
    echo "  export ANTHROPIC_API_KEY='sk-ant-api03-...'"
    echo ""
    echo "Or add to ~/.zshrc for permanent setup:"
    echo "  echo 'export ANTHROPIC_API_KEY=\"your-key\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Run translation script
python3 scripts/translate_top_words.py data/dictionary_full_multilingual.sqlite

echo ""
echo "To use the translated database:"
echo "  cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite"
echo "  cd NichiDict && xcodebuild -scheme NichiDict build"
