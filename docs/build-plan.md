# notebook build plan

all visible product text in the app uses lowercase lettering. this is a native swiftui ios app with typed local adapters for the requested external model and processing stack.

## source context

- comet card interaction reference: https://ui.aceternity.com/components/comet-card
- aceternity components reference: https://ui.aceternity.com/components
- gooey input reference: https://ui.aceternity.com/components/gooey-input
- direction aware hover reference: https://ui.aceternity.com/components/direction-aware-hover
- page flip interaction reference: https://github.com/Nodlik/StPageFlip
- segmentation and note-region isolation: https://github.com/facebookresearch/sam2
- 3d object segmentation and reconstruction: https://github.com/facebookresearch/sam-3d-objects
- single-image 3d generation for notebook object exploration: https://github.com/VAST-AI-Research/TripoSR
- 3d refinement/render support: https://github.com/blender/blender
- web 3d rendering / notebook motion prototype layer: https://github.com/mrdoob/three.js
- image preprocessing / perspective correction / scan cleanup: https://github.com/opencv/opencv
- handwriting recognition: https://github.com/microsoft/unilm/tree/master/trocr
- subject classification / multimodal note understanding / page q&a: gemma 4 12b it
- pdf extraction: pdf data extractor pagewise
- tts / ai reading voice / optional user voice replication: https://huggingface.co/spaces/OpenMOSS-Team/MOSS-TTS-v1.5/tree/main
- fast on-device tts option: https://github.com/hexgrad/kokoro
- voice transcription option: https://github.com/SYSTRAN/faster-whisper
- spaced repetition / memory scheduling: https://github.com/open-spaced-repetition
- animation system guidance: https://motion.dev/docs/react and https://motion.dev/docs/react-gestures
- floating action button motion reference: https://motion.dev/examples/react-floating-action-button
- ios design quality guidance: https://developer.apple.com/design/human-interface-guidelines

## implementation shape

- native swiftui shell with auth, shelf, scan, notebook, study, and voice setup screens.
- composition notebook cards use swiftui drag gestures, 3d rotation, scale, layered parallax, dense speckled composition-cover rendering, and spring return behavior inspired by the comet card reference.
- search, email, course entry, and subject setup use a native swiftui version of the gooey input idea: compact glass fields, breathing internal light, and typography that changes gently while typing.
- notebooks and study flashcards use direction aware lighting so touch location changes sheen, depth, and perceived material response on mobile.
- notebook pages use a native swiftui page-turn reader inspired by stpageflip's mobile page turning model, with swipe thresholds, page shadows, and perspective rotation.
- scan flow uses a cinematic local capture rehearsal with edge guides, scan sweep, processing phases, and an animated page-to-notebook handoff.
- models are defined for user, subject notebook, page, scan job, extracted content, flashcard, review state, ai action, and voice profile.
- service adapters are protocol-based so opencv, sam 2, sam 3d objects, surya, gemma, pdf extraction, moss-tts, kokoro, faster-whisper, triposr, and open spaced repetition can be wired behind the same app surfaces cleanly.
- voice replication uses the moss-tts v1.5 hugging face space model id `OpenMOSS-Team/MOSS-TTS-v1.5`; personalized playback uses clone mode with the recorded onboarding audio samples as reference audio, matching the space's `run_inference` path.
- liquid glass uses native swiftui glass APIs on ios 26 with material fallbacks on earlier ios targets.
