#!/usr/bin/env python3
"""Inner conversion script — runs inside a venv with compatible torch/coremltools."""

import os
import shutil
import numpy as np
import torch
import torch.nn as nn
import coremltools as ct
from transformers import AutoModel, AutoTokenizer

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
SEQ_LEN = 128
OUTPUT_DIR = os.path.expanduser("~/.familiar/knowledge")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "MiniLM.mlpackage")
os.makedirs(OUTPUT_DIR, exist_ok=True)

print(f"torch={torch.__version__}, coremltools={ct.__version__}")

print("Loading model...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME)
model.eval()

# Save vocab
vocab_path = os.path.join(OUTPUT_DIR, "vocab.txt")
vocab = tokenizer.get_vocab()
sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])
with open(vocab_path, "w") as f:
    for token, _ in sorted_vocab:
        f.write(token + "\n")
print(f"vocab.txt: {len(sorted_vocab)} tokens")

class MiniLMPooled(nn.Module):
    def __init__(self, transformer):
        super().__init__()
        self.transformer = transformer

    def forward(self, input_ids, attention_mask):
        out = self.transformer(input_ids=input_ids, attention_mask=attention_mask)
        emb = out.last_hidden_state
        mask = attention_mask.unsqueeze(-1).float()
        pooled = (emb * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
        return torch.nn.functional.normalize(pooled, p=2, dim=1)

wrapped = MiniLMPooled(model)
wrapped.eval()

dummy_ids = torch.zeros(1, SEQ_LEN, dtype=torch.int32)
dummy_mask = torch.ones(1, SEQ_LEN, dtype=torch.int32)

print("Tracing...")
traced = torch.jit.trace(wrapped, (dummy_ids, dummy_mask))

print("Converting to CoreML...")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, SEQ_LEN), dtype=np.int32),
    ],
    outputs=[ct.TensorType(name="embedding")],
    minimum_deployment_target=ct.target.macOS15,
    compute_precision=ct.precision.FLOAT16,
)

if os.path.exists(OUTPUT_PATH):
    shutil.rmtree(OUTPUT_PATH)
mlmodel.save(OUTPUT_PATH)
model_size = sum(f.stat().st_size for f in __import__('pathlib').Path(OUTPUT_PATH).rglob('*') if f.is_file())
print(f"CoreML saved: {model_size / 1024 / 1024:.1f} MB -> {OUTPUT_PATH}")

# Validate
print("Validating...")
test_text = "This is a test sentence for semantic search."
enc = tokenizer(test_text, padding="max_length", max_length=SEQ_LEN, truncation=True, return_tensors="pt")

with torch.no_grad():
    pt_emb = wrapped(enc["input_ids"].int(), enc["attention_mask"].int()).numpy().flatten()

pred = mlmodel.predict({
    "input_ids": enc["input_ids"].numpy().astype(np.int32),
    "attention_mask": enc["attention_mask"].numpy().astype(np.int32),
})
cml_emb = pred["embedding"].flatten()

cos_sim = np.dot(pt_emb, cml_emb) / (np.linalg.norm(pt_emb) * np.linalg.norm(cml_emb))
print(f"Cosine similarity: {cos_sim:.6f}")
print(f"Embedding dim: {len(cml_emb)}")
print("Done!")
