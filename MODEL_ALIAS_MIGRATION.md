# Model Alias Migration Matrix — Stand 2026-10-12

**Status:** KEINE Änderungen durchgeführt. Nur Analyse.

---

## Migrationsmatrix

| Alias | ID | Größe | Status | Aktion | Begründung |
|---|---|---|---|---|---|
| `qwen2.5-coder:14b` | `845dbda0ea48` | 7.6B | **REMOVE_CANDIDATE** | Umbenennen auf `qwen2.5-coder:7b` | Falsche Größe im Namen; 2 Referenzen |
| `qwen2.5-coder:7b` | `845dbda0ea48` | 7.6B | **KEEP** | — | Korrekte Bezeichnung, gleicher Inhalt |
| `qwen2.5:7b` | `845dbda0ea48` | 7.6B | **KEEP** | — | Basis-Modell, gleicher Inhalt |
| `qwen2.5-coder:7b-recovered-3` | `dae161e27b0e` | 7.6B | **UNKNOWN** | Prüfen ob identisch oder Recovery | Andere ID, gleiche Parameter |
| `llama3:latest` | `365c0bd3c000` | 8B | **KEEP** | — | Alias für `llama3:8b` |
| `llama3:8b` | `365c0bd3c000` | 8B | **KEEP** | — | Korrekte Bezeichnung |
| `mistral:latest` | `3944fe81ec14` | 7B | **KEEP** | — | Alias für `mistral:7b` |
| `mistral:7b` | `3944fe81ec14` | 7B | **KEEP** | — | Korrekte Bezeichnung |
| `phi3:mini` | `4f2222927938` | 3.8B | **KEEP** | — | Alias für `phi3:3.8b` |
| `phi3:3.8b` | `4f2222927938` | 3.8B | **KEEP** | — | Korrekte Bezeichnung |
| `Mistral:latest` | `6577803aa9a0` | 4.4B | **UNKNOWN** | Verschiedenes Modell? | Andere ID als `mistral:latest` |

---

## Empfehlung: Kanonischer Modellbestand

### Für Coding (Ryzen)

| Zweck | Empfohlen | Größe | Grund |
|---|---|---|---|
| Schnelles Coding | `qwen2.5-coder:7b` | 4.7 GB | 80 tok/s, ausreichend für meisten Code |
| Komplexes Coding | `hf.co/bartowski/Qwen_Qwen3-14B-GGUF:Q4_K_M` | 9.0 GB | 14.8B, thinking-fähig |
| Coding Klein | `qwen2.5-coder:3b` | 1.9 GB | Für schnelle Klassifikation |

### Für Reasoning (Ryzen)

| Zweck | Empfohlen | Größe | Grund |
|---|---|---|---|
| Reasoning | `local-deepseek-r1-distill-qwen-14b` | 9.0 GB | 14B Distill |
| Reasoning schnell | `deepseek-r1:7b` | 4.7 GB | 7B Variante |

### Für Allgemein (Ryzen)

| Zweck | Empfohlen | Größe | Grund |
|---|---|---|---|
| Default | `qwen3:8b` | 5.2 GB | Neu, schnell, gut |
| Deutsch | `openclaw-deutsch:latest` | 8.2 GB | Deutsch-spezifisch |

### Für Embeddings

| Zweck | Empfohlen | Größe | Grund |
|---|---|---|---|
| Embeddings | `nomic-embed-text:latest` | 274 MB | Standard |

### Für Bildanalyse

| Zweck | Empfohlen | Größe | Grund |
|---|---|---|---|
| Vision | `moondream:1.8b` | 1.7 GB | Klein, schnell |

---

## Abhängigkeitsprüfung

### Dateien mit Referenzen

| Datei | Referenz | Aktion nötig |
|---|---|---|
| `shadowmaker-ai-model-router:13` | `qwen2.5-coder:14b` | Ja — auf `:7b` ändern |
| `shadowmaker-telegram-skill-bot:764,774` | `qwen2.5-coder:14b` | Ja — auf `:7b` ändern |

### Keine Referenzen in

- PHOENIX Config
- OpenCode Config
- systemd Units
- GitHub Actions

---

## Sicherheitsregeln

1. **Keine Löschung** ohne explizite Freigabe
2. **Kein Download** neuer Modelle ohne GPU-Speicherprüfung
3. **Keine Dienständerung** bei Alias-Umbenennung
4. **Referenzen zuerst aktualisieren**, dann Alias entfernen
5. **Backup** des aktuellen `ollama list` Auszugs

---

## Offene Fragen

1. Ist `qwen2.5-coder:7b-recovered-3` ein Duplikat oder eine Recovery-Variante?
2. Ist `Mistral:latest` (`6577803aa9a0`) ein anderes Modell als `mistral:latest` (`3944fe81ec14`)?
3. Sollen die IHK-spezifischen Modelle (`ihk-*`) als eigene Kategorie geführt werden?
