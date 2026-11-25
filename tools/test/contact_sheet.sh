#!/bin/bash
# contact_sheet.sh <run> <from_s> [max=36] : builds /tmp/cmp/r<run>.jpg with the screenshots of that run from that second on.
# Runs on the host; needs python3 with Pillow.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"
mkdir -p /tmp/cmp
cd "$WORK/shots" && python3 - "$1" "$2" "${3:-36}" <<PY
from PIL import Image, ImageDraw
import glob, sys
r, d, m = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
fs = sorted(glob.glob(f"r{r}_*.png"), key=lambda f: int(f.split("_")[1][:-5]))
fs = [f for f in fs if int(f.split("_")[1][:-5]) >= d][:m]
im = Image.new("RGB", (9*256, ((len(fs)+8)//9)*154))
for i, f in enumerate(fs):
    t = Image.open(f).convert("RGB").resize((256, 144)); ImageDraw.Draw(t).text((4, 4), f.split("_")[1][:-4], fill=(255, 255, 0)); im.paste(t, ((i % 9)*256, (i//9)*154))
im.save(f"/tmp/cmp/r{r}.jpg", quality=80); print(len(fs))
PY
