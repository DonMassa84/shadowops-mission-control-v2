# ShadowOps Remote-Only AI Execution Policy

Status: CANONICAL REPOSITORY POLICY

ShadowOps coding and AI-assisted development must not execute local language models.

## Policy

```text
AI_EXECUTION_POLICY=REMOTE_ONLY
```

For coding-agent execution:

- local Ollama models are forbidden;
- local LM Studio models are forbidden;
- local llama.cpp/llamacpp model endpoints are forbidden;
- the repository must not configure a local model provider as the default OpenCode model;
- `scripts/shadowops-coder.sh` requires an explicit remote `provider/model` identifier;
- the exact identifier must be present in `opencode models` before execution;
- the model passed through OpenCode CLI `--model` is the authoritative model identity for the run;
- a UI label is not sufficient evidence of the actual model used;
- no fallback from a remote model to a local model is allowed.

The ShadowOps MCP process may remain local because it is a read-only runtime interface, not an AI model. Phoenix/Elixir services, tests, build tools and local state are likewise not affected by this policy.

## Required launch pattern

First identify an available remote model:

```bash
opencode models
```

Then run with its exact identifier:

```bash
SHADOWOPS_CODER_MODEL='provider/model' \
  SHADOWOPS_CODER_TIMEOUT=45m \
  bash scripts/shadowops-coder.sh --next
```

If no explicit remote model is selected, the launcher must fail closed with:

```text
SHADOWOPS_CODER=BLOCKED_REMOTE_MODEL_REQUIRED
```

If a known local provider is selected, the launcher must fail closed with:

```text
SHADOWOPS_CODER=BLOCKED_LOCAL_AI_FORBIDDEN
```

## Future AI instructions

Do not reintroduce:

- `model: ollama/...`;
- `small_model: ollama/...`;
- a repository-local Ollama provider block;
- implicit local-model fallback;
- automatic local model discovery or model pulling for coding tasks.

If this policy is to be changed later, it requires an explicit human request. Do not infer permission from an installed local model, existing Ollama service, historical documentation or previous commits.
