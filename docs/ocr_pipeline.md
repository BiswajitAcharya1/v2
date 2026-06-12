# marginalia ocr pipeline

marginalia uses an ensemble because no single OCR engine is reliable enough for severe cursive or doctor-note handwriting.

## order of work

1. create multiple image variants for the scan: original, paper-normalized, ink boost, pencil boost, shadow lift, cursive recovery, thin-stroke recovery, and joined-script recovery.
2. send remote-safe variants to configured OCR engines:
   - `MISTRAL_OCR_API_KEY` or `MistralOCRAPIKey`
   - `GOOGLE_VISION_API_KEY` or `GoogleVisionAPIKey`
   - `AZURE_DOCUMENT_INTELLIGENCE_KEY` or `AzureDocumentIntelligenceAPIKey`
   - `AZURE_VISION_API_KEY` or `AzureVisionAPIKey`
   - `CHANDRA_OCR_ENDPOINT` or `ChandraOCREndpoint`
   - `SURYA_OCR_ENDPOINT` or `SuryaOCREndpoint`
   - `VISION_LANGUAGE_OCR_ENDPOINT` or `VisionLanguageOCREndpoint`
3. run Apple Vision locally as an offline fallback.
4. build a consensus transcript from all engines.
5. if a hosted vision-language endpoint is configured, adjudicate the final transcript using the image plus all candidate transcripts.
6. run reliability scoring so symbol-heavy, fragmented, or contradictory OCR does not win only because one provider reported high confidence.

`OCRPipelineReadiness.isDoctorNoteReady` is true only when at least one serious remote OCR engine is configured and the vision-language adjudicator is configured. If it is false, the app can still scan, but it should be treated as fallback mode rather than doctor-note-grade OCR.

## required for best messy handwriting accuracy

The strongest mode needs `VISION_LANGUAGE_OCR_ENDPOINT` backed by a vision-language model that can inspect the original image and compare candidate transcripts. This can be a Gemma vision proxy or another hosted VLM. The endpoint should accept JSON:

```json
{
  "model": "gemma-4-12b-it",
  "image_base64": "<jpeg>",
  "prompt": "<instructions>",
  "response_format": "lines"
}
```

The response can be any of these shapes:

```json
{ "text": "..." }
{ "lines": ["...", "..."] }
{ "output_text": "..." }
{ "choices": [{ "message": { "content": "..." } }] }
```

Without this endpoint, marginalia still uses Mistral OCR, Google Vision, Azure Document Intelligence, Chandra, Surya, and Apple Vision when configured, but the final doctor-note correction pass is not available.

## strongest current configuration

- set `MistralOCRModel` or `MISTRAL_OCR_MODEL` to the best available Mistral OCR model for the account, or leave it as `mistral-ocr-latest`.
- set `GoogleVisionOCRModel` or `GOOGLE_VISION_OCR_MODEL` to `builtin/weekly` for the newest Google OCR release, or `builtin/latest` for a less aggressive model.
- set `CHANDRA_OCR_ENDPOINT` to a hosted or self-hosted Chandra OCR 2 service. marginalia tries multipart image upload first, then JSON base64 upload with `format: "markdown"` and `mode: "accurate"`. responses can return markdown, html, text, lines, pages, result, results, or blocks.
- set `SURYA_OCR_ENDPOINT` to a hosted or self-hosted Surya OCR 2 service for layout and table recovery.
- set `VISION_LANGUAGE_OCR_ENDPOINT` to a hosted vision-language adjudicator for the final messy-handwriting correction pass.

## measuring ugly handwriting accuracy

Use `tools/evaluate_ocr.py` to score transcripts against hand-transcribed ground truth:

```bash
python3 tools/evaluate_ocr.py fixtures/doctor_note_truth.txt outputs/marginalia_ocr.txt
python3 tools/evaluate_ocr.py fixtures/ocr_truth --predictions outputs/ocr_predictions
```

Track:

- `cer`: character error rate. lower is better.
- `wer`: word error rate. lower is better.
- `line_recall`: exact line preservation. higher is better.

The goal is not proven by a green build. It is proven only when the configured OCR ensemble scores well on real messy handwriting images, including cursive, faint pencil, dense notes, crossed-out text, formulas, and doctor-note-style handwriting.
