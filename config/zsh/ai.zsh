get-keys() {
  export OPENROUTER_API_KEY=$(op read "op://Private/OpenRouter/credential")
  export ZAI_API_KEY=$(op read "op://Private/ZAI/credential")
  export ANTHROPIC_API_KEY=$(op read "op://Private/Anthropic/credential")
  export GEMINI_API_KEY=$(op read "op://Private/Gemini/credential")
  echo "🔑 AI keys loaded."
}
