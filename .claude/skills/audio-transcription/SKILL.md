---
name: audio-transcription
description: Use when transcribing a local audio file on Sean's Mac (voice messages, .caf/.m4a/.mp3/.wav, any language). Covers decoding without system ffmpeg, running Whisper via MLX, forcing language, and cleanup.
---

# Local audio transcription (macOS, MLX)

Transcribe an audio file locally — no cloud, no API. Tested on Apple Silicon. Works for `.caf` (Messages voice notes), `.m4a`, `.mp3`, `.wav`, etc.

## Recipe

1. **Decode to 16kHz mono WAV** with the built-in macOS tool (no system ffmpeg needed):

   ```sh
   afconvert -d LEI16@16000 -c 1 -f WAVE "input.caf" /tmp/audio.wav
   afinfo /tmp/audio.wav   # sanity-check duration / format
   ```

2. **Get an ffmpeg binary** (MLX transcribers shell out to ffmpeg internally; the Mac has none by default — avoid `brew install ffmpeg`):

   ```sh
   FF=$(uv run --with imageio-ffmpeg python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")
   mkdir -p /tmp/ffbin && ln -sf "$FF" /tmp/ffbin/ffmpeg
   export PATH="/tmp/ffbin:$PATH"
   ```

3. **Transcribe with Whisper turbo via MLX**, forcing the language for anything non-English:
   ```sh
   uvx --from mlx-whisper mlx_whisper \
     --model mlx-community/whisper-large-v3-turbo \
     --language fr \
     --output-format txt --output-dir /tmp /tmp/audio.wav
   cat /tmp/audio.txt
   ```
   Use the ISO code for the spoken language (`fr`, `es`, `de`, `pt`, `en`, …). Omit `--language` only if you genuinely don't know it and the audio is English.

## Model choice — the important bit

- **Use Whisper (`whisper-large-v3-turbo`) for any non-English audio.** It's accurate and lets you pin the language.
- **Do NOT use Parakeet v3** (the model Handy ships) for non-English. It code-switches into English/garbage and its `parakeet-mlx` CLI has **no language-force flag**. Handy also ships it as ONNX, not CLI-drivable, so its copy can't be reused anyway.

## Gotchas

- **Whisper end-hallucination:** Whisper often emits a repeated phrase with timestamps _past the real audio end_ (e.g. a 60s clip showing "…" at 01:01). Drop anything beyond the true duration from `afinfo`.
- **Low-confidence words:** flag proper nouns / names / company names as uncertain rather than asserting them — confirm against context the user has.
- **Disk:** the MLX/HF model weights are large (~1.5GB Whisper turbo, ~2.3GB Parakeet) plus uv deps. After a one-off job, reclaim with `uv cache prune` and delete unwanted weights under `~/.cache/huggingface/hub/`. Re-runs reuse the cache (no re-download).

## When asked to also translate

Transcribe first (above), then translate the resulting text. Present both the original-language transcript and the English translation, and keep the uncertainty flags.
