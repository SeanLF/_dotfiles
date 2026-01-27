# Text-to-Speech with Kokoro MLX

Generate high-quality speech audio from text using Kokoro TTS on Apple Silicon.

## Usage

```
/tts "Text to speak"
/tts path/to/file.txt
/tts path/to/file.html
```

## Arguments

- `$ARGUMENTS` - Either quoted text or a file path (.txt, .html, .md)

## Instructions

Generate speech audio using Kokoro MLX. This runs natively on Apple Silicon and is very fast (~25x real-time).

### Steps

1. **Parse input**: Determine if `$ARGUMENTS` is:
   - Quoted text → use directly
   - A file path → read and extract text content
   - For HTML: strip tags, decode entities, extract readable text
   - For Markdown: convert to plain text

2. **Preprocess text for TTS**:
   - Expand common abbreviations: "U.S." → "U.S.", "US" (standalone) → "U.S.", "UK" → "U.K.", "EU" → "E.U."
   - Remove URLs (they sound terrible spoken)
   - Remove emoji (Kokoro strips them anyway)
   - Normalize whitespace

3. **Generate audio** using this command:
   ```bash
   cd /tmp && uv run --python 3.12 --with "mlx-audio[tts]" python << 'PYEOF'
   from mlx_audio.tts.generate import load_model, generate_audio
   import soundfile as sf
   import numpy as np
   import glob

   text = """YOUR_PREPROCESSED_TEXT_HERE"""

   print('Loading Kokoro model...')
   model = load_model('mlx-community/Kokoro-82M-bf16')

   print('Generating audio...')
   audio = generate_audio(
       model=model,
       text=text,
       voice='af_heart',  # American female, warm tone
       lang_code='a',     # American English
       verbose=True
   )

   # Combine chunks if multiple were generated
   files = sorted(glob.glob('audio_*.wav'), key=lambda x: int(x.split('_')[1].split('.')[0]))
   if files:
       all_audio = []
       for f in files:
           data, sr = sf.read(f)
           all_audio.append(data)
       combined = np.concatenate(all_audio)
       sf.write('OUTPUT_PATH', combined, 24000)
       print(f'Saved to OUTPUT_PATH')
       print(f'Duration: {len(combined)/24000:.1f} seconds')
   PYEOF
   ```

4. **Output file naming**:
   - If input was a file: use same name with `.wav` extension in same directory
   - If input was text: save to `./tts-output.wav` or ask user

5. **Play the audio** with `open OUTPUT_PATH` so user can hear it immediately

### Available voices

- `af_heart` - American female, warm (default)
- `af_bella` - American female
- `af_nova` - American female
- `am_adam` - American male
- `am_michael` - American male
- `bf_emma` - British female
- `bf_alice` - British female
- `bm_daniel` - British male

User can request a different voice and you should use the appropriate code.

### Notes

- Requires Python 3.12 (spacy/pydantic incompatible with 3.14)
- First run downloads ~300MB model to HuggingFace cache
- Runs on Apple Silicon GPU via MLX - very fast
- Peak memory ~3GB during generation
