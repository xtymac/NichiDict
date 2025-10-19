#!/bin/bash

# Convenience script to run OpenAI translation
# Cost: ~$0.25 for 5000 words (6x cheaper than Claude!)

cd "$(dirname "$0")/.."

# Check if API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ Error: OPENAI_API_KEY not set"
    echo ""
    echo "Please set your OpenAI API key:"
    echo "  export OPENAI_API_KEY='sk-proj-...'"
    echo ""
    echo "Or add to ~/.zshrc for permanent setup:"
    echo "  echo 'export OPENAI_API_KEY=\"your-key\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
    echo ""
    echo "Get your API key at: https://platform.openai.com/api-keys"
    exit 1
fi

echo "Using OpenAI GPT-4o mini"
echo "Cost: ~\$0.25 for 5000 words (6x cheaper than Claude!)"
echo ""

# Activate virtual environment
source venv/bin/activate

# Run translation script
python3 scripts/translate_with_openai.py data/dictionary_full_multilingual.sqlite

echo ""
echo "Next steps:"
echo "  1. Copy database: cp data/dictionary_full_multilingual.sqlite NichiDict/Resources/seed.sqlite"
echo "  2. Rebuild app: cd NichiDict && xcodebuild -scheme NichiDict build"
echo "  3. Reinstall to simulator"
