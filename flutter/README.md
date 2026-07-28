# Beatrice — Flutter App

Beatrice voice assistant — Eburon AI Gemini Live API.

## MobileUse Agent: AI Provider Aliases

| Alias        | Alias Name        | Base URL                                                                 | API Key              | Model Alias (used in UI) | Resolves To                   | Notes                                |
|--------------|-------------------|--------------------------------------------------------------------------|----------------------|--------------------------|-------------------------------|--------------------------------------|
| Gemini       | gemini            | `https://generativelanguage.googleapis.com/v1beta/openai/`               | 🔑 Hardcoded         | `gemini`                 | `gemini-2.0-flash`           | Google Gemini API                    |
| Groq         | groq              | `https://api.groq.com/openai/v1`                                         | 🔑 Hardcoded         | `groq`                   | `llama-3.3-70b-versatile`    | Groq LPU inference                   |
| OllamaCloud  | ollamacloud       | `https://api.ollama.ai/v1`                                               | 🔑 Hardcoded         | `ollamacloud`            | `gemma3:4b`                  | Ollama cloud API                     |
| Ollama       | ollama            | `http://localhost:11434/v1`                                              | `ollama`             | `ollama`                 | `gemma3:4b`                  | Local model via Termux               |
| OpenCode     | opencode          | `http://localhost:4096/v1`                                               | `dummy`              | `opencode`               | `deepseek-chat`              | Self-hosted Termux proot-distro      |
| DeepSeek     | deepseek          | `https://api.deepseek.com`                                               | User-provided        | `deepseek`               | `deepseek-chat`              | DeepSeek chat API                    |
| NVIDIA       | nvidia            | `https://integrate.api.nvidia.com/v1`                                    | User-provided        | `nvidia`                 | `z-ai/glm-5.2`               | NVIDIA NIM free tier (14+ models)    |
| OpenRouter   | openrouter        | `https://openrouter.ai/api/v1`                                           | User-provided        | `openrouter`             | `openai/gpt-oss-120b:free`   | Multi-model router                   |

> 🔑 **Hardcoded keys** are pre-filled automatically when you tap the provider chip in Settings.
> Start typing the alias name in the settings to auto-select the preset.
>
> 💡 The **Model** field uses short alias names (`gemini`, `groq`, etc.) which are
> automatically resolved to full API model names (`gemini-2.0-flash`, `llama-3.3-70b-versatile`, etc.)
> when making requests. You can still type a custom full model name directly — it passes through as-is.

## Service Classes

| Class              | Alias Name   | File Path                                      | Description                                     |
|--------------------|--------------|-----------------------------------------------|-------------------------------------------------|
| `MobileUseAiService` | AiSvc      | `lib/data/services/mobile_use_ai_service.dart` | Multi-provider AI client (OpenAI-compatible)     |
| `MobileUseActionHandler` | ActionHndlr | `lib/data/services/mobile_use_action_handler.dart` | Routes AI actions to device control services      |
| `DeviceControlService` | DevCtrl    | `lib/data/services/device_control_service.dart` | HTTP bridge to MobileUse server on localhost      |
| `AgentAction`      | AgentAct    | `lib/data/models/agent_action.dart`            | Action model for device control instructions      |

## Flutter Development

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
