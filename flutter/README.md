# Beatrice — Flutter App

Beatrice voice assistant — Eburon AI Gemini Live API.

## MobileUse Agent: Provider Aliases

| Alias           | Used In Settings | Base URL                                                          | API Key        | Notes                      |
|-----------------|------------------|-------------------------------------------------------------------|----------------|----------------------------|
| **eburon-os**   | `eburon-os`      | `https://generativelanguage.googleapis.com/v1beta/openai/`        | 🔑 Hardcoded   | Gemini API                 |
| **eburon-beta** | `eburon-beta`    | `https://api.groq.com/openai/v1`                                  | 🔑 Hardcoded   | Groq LPU                   |
| **eburon-cloud**| `eburon-cloud`   | `https://api.ollama.ai/v1`                                        | 🔑 Hardcoded   | Ollama Cloud               |
| **eburon**      | `eburon`         | `http://localhost:11434/v1`                                       | `ollama`       | Ollama local (Termux)      |
| **openbox**     | `openbox`        | `http://127.0.0.1:4096/v1`                                        | `dummy`        | OpenCode (Termux proot)    |
| deepseek        | `deepseek`       | `https://api.deepseek.com`                                        | User-provided  | DeepSeek chat API          |
| nvidia          | `nvidia`         | `https://integrate.api.nvidia.com/v1`                             | User-provided  | NVIDIA NIM free tier       |
| openrouter      | `openrouter`     | `https://openrouter.ai/api/v1`                                    | User-provided  | Multi-model router         |

> 🔑 **Hardcoded keys** pre-filled automatically when you tap the chip in Settings.
> 💡 Pick an alias from the dropdown — the real model name is resolved internally.

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
