#!/usr/bin/env python3
"""Convert all-MiniLM-L6-v2 to CoreML using a venv with compatible versions."""

import subprocess
import sys
import os

VENV_DIR = "/tmp/miniml-convert-venv"
OUTPUT_DIR = os.path.expanduser("~/.familiar/knowledge")
SCRIPT = os.path.join(os.path.dirname(__file__), "_convert_inner.py")

# Create venv with compatible versions
if not os.path.exists(VENV_DIR):
    print("Creating venv with compatible torch/coremltools versions...")
    subprocess.check_call([sys.executable, "-m", "venv", VENV_DIR])
    pip = os.path.join(VENV_DIR, "bin", "pip")
    subprocess.check_call([pip, "install", "-q", "torch==2.7.0", "coremltools==8.1",
                           "transformers", "numpy<2"])
    print("Venv ready.")

# Run the inner script in the venv
python = os.path.join(VENV_DIR, "bin", "python")
subprocess.check_call([python, SCRIPT])
