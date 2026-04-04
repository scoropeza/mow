#!/bin/bash
# Export ModernBERT disfluency token classifier to CoreML for on-device inference.
#
# Downloads the HuggingFace model, exports to ONNX, converts to CoreML (.mlpackage).
# Output: models/DisfluencyClassifier.mlpackage (ready to add to Xcode project)
#
# Requirements: Python 3.10+ with pip. Creates a temporary venv.
# Run from the repo root: ./scripts/export-disfluency-model.sh

set -euo pipefail

MODEL_ID="arielcerdap/modernbert-base-multiclass-disfluency-v2"
OUTPUT_DIR="models"
VENV_DIR=".venv-export"
ONNX_DIR="$OUTPUT_DIR/onnx-tmp"
COREML_OUT="$OUTPUT_DIR/DisfluencyClassifier.mlpackage"

echo "=== ModernBERT Disfluency Model → CoreML Export ==="
echo "Model: $MODEL_ID"
echo ""

# Step 1: Create virtual environment
PYTHON="${PYTHON:-python3.12}"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment with $PYTHON..."
    "$PYTHON" -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# Step 2: Install dependencies
echo "Installing dependencies..."
pip install --quiet --upgrade pip
pip install --quiet torch transformers "optimum[onnxruntime]" onnx onnxruntime coremltools numpy

# Step 3: Export to ONNX
echo ""
echo "Exporting $MODEL_ID to ONNX..."
mkdir -p "$ONNX_DIR"
python3 -c "
from optimum.exporters.onnx import main_export
main_export('${MODEL_ID}', '${ONNX_DIR}', task='token-classification')
"
echo "ONNX export complete: $ONNX_DIR"

# Step 4: Convert ONNX to CoreML
echo ""
echo "Converting ONNX to CoreML..."
mkdir -p "$OUTPUT_DIR"
python3 - "$ONNX_DIR" "$COREML_OUT" << 'PYEOF'
import coremltools as ct
import os
import sys

onnx_dir = sys.argv[1]
coreml_out = sys.argv[2]

# Find the ONNX file
onnx_path = None
for f in os.listdir(onnx_dir):
    if f.endswith(".onnx"):
        onnx_path = os.path.join(onnx_dir, f)
        break

if not onnx_path:
    print("ERROR: No .onnx file found in", onnx_dir)
    sys.exit(1)

print(f"Converting {onnx_path}...")

model = ct.converters.convert(
    onnx_path,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.macOS14,
    compute_precision=ct.precision.FLOAT16,
)

model.author = "arielcerdap (HuggingFace)"
model.short_description = "ModernBERT disfluency token classifier (FP/RP/RV/PW detection)"
model.version = "1.0"

model.save(coreml_out)
print(f"CoreML model saved to {coreml_out}")

size_mb = sum(
    os.path.getsize(os.path.join(dp, f))
    for dp, _, filenames in os.walk(coreml_out)
    for f in filenames
) / (1024 * 1024)
print(f"Model size: {size_mb:.1f} MB")
PYEOF

# Step 5: Export tokenizer and label map
echo ""
echo "Exporting tokenizer and label map..."
python3 - "$MODEL_ID" "$OUTPUT_DIR" << 'PYEOF'
from transformers import AutoTokenizer, AutoConfig
import json
import os
import sys

model_id = sys.argv[1]
output_dir = sys.argv[2]

tokenizer = AutoTokenizer.from_pretrained(model_id)
tokenizer.save_pretrained(os.path.join(output_dir, "tokenizer"))

config = AutoConfig.from_pretrained(model_id)
if hasattr(config, "id2label"):
    with open(os.path.join(output_dir, "label_map.json"), "w") as f:
        json.dump(config.id2label, f, indent=2)
    print(f"Label map: {config.id2label}")

print(f"Tokenizer saved to {output_dir}/tokenizer/")
PYEOF

# Step 6: Cleanup
echo ""
echo "Cleaning up ONNX intermediate files..."
rm -rf "$ONNX_DIR"

echo ""
echo "=== Export complete ==="
echo "CoreML model: $COREML_OUT"
echo "Tokenizer:    $OUTPUT_DIR/tokenizer/"
echo "Label map:    $OUTPUT_DIR/label_map.json"
echo ""
echo "Next steps:"
echo "  1. Add $COREML_OUT to the Xcode project"
echo "  2. Labels: O=keep, FP=filled pause, RP=repetition, RV=revision, PW=partial word"
echo "  3. Remove words tagged FP/RP/RV/PW, keep words tagged O"
