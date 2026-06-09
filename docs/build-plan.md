# notebook build plan

all visible product text in the app uses lowercase lettering. this demo is a native swiftui ios app with typed mock adapters for the requested external model and processing stack.

## source context

- comet card interaction reference: https://ui.aceternity.com/components/comet-card
- aceternity components reference: https://ui.aceternity.com/components
- segmentation and note-region isolation: https://github.com/facebookresearch/sam2
- single-image 3d generation for notebook object exploration: https://github.com/VAST-AI-Research/TripoSR
- 3d refinement/render support: https://github.com/blender/blender
- web 3d rendering / notebook motion prototype layer: https://github.com/mrdoob/three.js
- image preprocessing / perspective correction / scan cleanup: https://github.com/opencv/opencv
- handwriting recognition: https://github.com/microsoft/unilm/tree/master/trocr
- subject classification / multimodal note understanding / page q&a: gemma 4 12b it
- pdf extraction: pdf data extractor pagewise
- tts / ai reading voice / optional user voice replication: moss-tts v1.5
- spaced repetition / memory scheduling: https://github.com/open-spaced-repetition
- animation system guidance: https://motion.dev/docs/react and https://motion.dev/docs/react-gestures
- ios design quality guidance: https://developer.apple.com/design/human-interface-guidelines

## implementation shape

- native swiftui shell with auth, shelf, scan, notebook, study, and voice setup screens.
- composition notebook cards use swiftui drag gestures, 3d rotation, scale, layered parallax, canvas marbling, and spring return behavior inspired by the comet card reference.
- scan flow is currently a cinematic mock capture with edge guides, scan sweep, processing phases, and an animated page-to-notebook handoff.
- models are defined for user, subject notebook, page, scan job, extracted content, flashcard, review state, ai action, and voice profile.
- service adapters are protocol-based so opencv, sam 2, trocr, gemma, pdf extraction, moss-tts, and open spaced repetition can replace the mocks cleanly.
- liquid glass uses native swiftui glass APIs on ios 26 with material fallbacks on earlier ios targets.
