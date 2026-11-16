# FluidAudio (trimmed local copy)

Source: https://github.com/FluidInference/FluidAudio, release **v0.18.3**
(commit 915a392a3b214205fcf4860cc3608bde35891d03 is the tag object; see `git log` upstream).
Licence: Apache 2.0 (`LICENSE`, unchanged).

Nourlo uses it for one thing: running the optional Parakeet TDT v3 speech
model on the phone (`smartmarket/Services/OfflineSpeechModel.swift`).

## What differs from upstream

No source file was edited. Left out:

- The `LuxTtsG2pResources` target and the prebuilt `NemoTextProcessing`
  xcframework (a 94 MB download used for text-to-speech text normalization).
- The command-line tool, tests and documentation.

`Sources/FluidAudio/TTS` and `Sources/FluidAudio/Diarizer` are kept: almost all
of their code is wrapped in `#if TTS` / `#if Diarizer` upstream and compiles to
nothing here, but a few shared types in them are used by the rest of the library.

`Package.swift` is ours: it declares only the speech-recognition library, the
same set the upstream package builds with `traits: []`.

## Updating

Copy `Sources/FluidAudio`, `Sources/FastClusterWrapper`
and `Sources/MachTaskSelfWrapper` from the new release, keep this `Package.swift`,
build, and update the version above.
