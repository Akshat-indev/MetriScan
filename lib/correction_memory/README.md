# Correction Memory

This is a temporary Phase 1 correction-memory stand-in for a future trained model.
It uses local similarity matching and verified OCR-pattern substitutions to improve
previously seen products and recurring OCR mistakes without training a model.

The module owns its fingerprinting, similarity, pattern correction, and SQLite
storage (`product_memory` and `pattern_corrections`). It is deliberately isolated
so it can be replaced wholesale when a trained model is ready; do not incrementally
move this logic into the OCR pipeline, rule engine, or shared utilities.

This does not generalize to genuinely new products or unseen wording/layouts.
