# Ollama Model Inventory — Stand 2026-10-12

**Host:** Ryzen · RTX 3060 12GB · Ollama 0.35.1
**Gesamt:** 50 Tags, 45 eindeutige Modell-IDs

---

## Alias-Gruppen (gleiche Modell-ID)

| Gruppe | Tags | ID | Tatsächliche Größe |
|---|---|---|---|
| **G1** | `qwen2.5:7b` = `qwen2.5-coder:7b` = `qwen2.5-coder:14b` | `845dbda0ea48` | **7.6B** (Qwen2) |
| **G2** | `llama3:latest` = `llama3:8b` | `365c0bd3c000` | 8B (Llama3) |
| **G3** | `mistral:7b` = `mistral:latest` | `3944fe81ec14` | 7B (Mistral) |
| **G4** | `phi3:mini` = `phi3:3.8b` | `4f2222927938` | 3.8B (Phi3) |

---

## Kritischer Befund: qwen2.5-coder:14b

```
Tag:                  qwen2.5-coder:14b
Modell-ID:            845dbda0ea48
Architektur:          qwen2
Parameter:            7.6B          ← NICHT 14B!
Quantisierung:        Q4_K_M
Context:              32768
System-Prompt:        generisch (nicht coder-spezifisch)
Inferenz-Speed:       80.79 tok/s   ← 7B-Geschwindigkeit
```

**Fazit:** Der Tag `qwen2.5-coder:14b` ist **falsch benannt**. Es handelt sich um dasselbe 7.6B-Modell wie `qwen2.5:7b`.

---

## Eindeutige Modelle (kein Alias)

| Tag | ID | Größe | Architektur | Verwendung |
|---|---|---|---|---|
| `hf.co/bartowski/Qwen_Qwen3-14B-GGUF:Q4_K_M` | `014a892455df` | 9.0 GB | **qwen3 14.8B** | ← Echtes 14B |
| `hf.co/bartowski/google_gemma-3-12b-it-qat-GGUF:Q4_K_M` | `669e9efe97c0` | 8.2 GB | gemma3 12B | Allgemein |
| `local-deepseek-r1-distill-qwen-14b-q4_k_m-15824eec` | `9c1c7e5059d8` | 9.0 GB | qwen2 14B | Reasoning |
| `ihk-projektarbeit-local:latest` | `a8371f9ce6a3` | 8.2 GB | — | IHK |
| `openclaw-reason:latest` | `d455c90e6cc5` | 9.0 GB | — | Reasoning |
| `openclaw-coder:latest` | `37f3cdbafeae` | 9.0 GB | — | Coding |
| `openclaw-default:latest` | `6fecf666de3c` | 9.0 GB | — | Default |
| `openclaw-deutsch:latest` | `25cd236c8b61` | 8.2 GB | — | Deutsch |
| `shadow-wizard:latest` | `63306069d5ba` | 7.4 GB | — | Custom |
| `wizardlm-13b-local:latest` | `6c364a314e23` | 7.4 GB | — | Custom |
| `shadow-direct:latest` | `999884425c42` | 5.2 GB | — | Custom |
| `qwen3:8b` | `500a1f067a9f` | 5.2 GB | qwen3 8B | Allgemein |
| `local-qwen3-8b-q4_k_m-2e772cab` | `6a0c2e7dd2c3` | 5.0 GB | qwen3 8B | Custom |
| `llama3.1:8b` | `46e0c10c039e` | 4.9 GB | llama3.1 8B | Allgemein |
| `qwen-coder-local:latest` | `bb49b88abfc8` | 5.2 GB | — | Coding |
| `deepseek-r1:7b` | `755ced02ce7b` | 4.7 GB | — | Reasoning |
| `storagegov-coder:latest` | `b930d5416964` | 4.7 GB | — | Coding |
| `storagegov-reason:latest` | `5d12b00d0b99` | 4.7 GB | — | Reasoning |
| `shadow-hermes:latest` | `ee2737b3a3c4` | 4.1 GB | — | Custom |
| `ihk-40-seiten-ausbau:latest` | `43a87f276885` | 4.7 GB | — | IHK |
| `ihk-planung-recovery:latest` | `3236126e4647` | 4.7 GB | — | IHK |
| `ihk-kapitel-repair:latest` | `4e075c00c053` | 4.7 GB | — | IHK |
| `shadow-opencode-qwen7b:latest` | `3f987cecca2f` | 4.7 GB | — | OpenCode |
| `qwen2.5-coder:7b-recovered-3` | `dae161e27b0e` | 4.7 GB | qwen2 7.6B | Recovered |
| `hf.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF:Q4_K_M` | `f218460127af` | 4.7 GB | qwen2 7B | Coder |
| `hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M` | `78a06ba3832b` | 2.0 GB | llama3.2 3B | Klein |
| `hf.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF:Q4_K_M` | `b77e948e63cc` | 2.5 GB | phi4 mini | Klein |
| `openclaw-fast:latest` | `d47b53cffc10` | 2.5 GB | — | Fast |
| `llama3.2:latest` | `a80c4f17acd5` | 2.0 GB | llama3.2 | Klein |
| `orca-mini:latest` | `2dbd9f439647` | 2.0 GB | — | Klein |
| `qwen2.5:3b` | `357c53fb659c` | 1.9 GB | qwen2 3B | Klein |
| `qwen2.5-coder:3b` | `f72c60cabf62` | 1.9 GB | qwen2 3B | Coder Klein |
| `local-shadowmaker-v4b-f16-cf7d8936` | `7d9b8ae5f7c1` | 3.1 GB | — | Custom |
| `local-shadowmaker-v9-f16-b21da2ed` | `f8e7c56d7b4f` | 3.1 GB | — | Custom |
| `gemma:2b` | `b50d6c999e59` | 1.7 GB | gemma 2B | Mini |
| `storagegov-small:latest` | `3378ff9a210c` | 1.7 GB | — | Klein |
| `starcoder2:3b` | `9f4ae0aff61e` | 1.7 GB | starcoder2 | Coding Klein |
| `moondream:1.8b` | `55fc3abd3867` | 1.7 GB | — | Bild |
| `llama3.2:1b` | `baf6a787fdff` | 1.3 GB | llama3.2 | Mini |
| `nomic-embed-text:latest` | `0a109f422b47` | 274 MB | — | Embedding |

---

## Referenzen auf qwen2.5-coder:14b

| Datei | Zeile | Verwendung |
|---|---|---|
| `shadowmaker-ai-model-router` | 13 | `DESKTOP_CODER_MODEL` Default |
| `shadowmaker-telegram-skill-bot` | 764, 774 | `/code` Befehl |

---

## Empfohlene kanonische Bezeichnungen

| Aktuell | Empfohlen | Grund |
|---|---|---|
| `qwen2.5-coder:14b` | `qwen2.5-coder:7b` | Ist 7.6B, nicht 14B |
| `qwen2.5-coder:14b` (wenn 14B gemeint) | `hf.co/bartowski/Qwen_Qwen3-14B-GGUF:Q4_K_M` | Echtes 14.8B |

---

**Keine Modelle gelöscht. Keine Downloads. Keine Dienständerungen.**
