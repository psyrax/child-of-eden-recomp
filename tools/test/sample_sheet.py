# sample_sheet.py <run> <step> : contact sheets /tmp/cmp/m<run>_<k>.jpg with one of every <step> screenshots (63 per sheet).
# For reviewing long runs. Reads work/shots (or $EDEN_WORK/shots); runs on the host; needs Pillow.
from PIL import Image, ImageDraw
import glob, sys, os
r, p = sys.argv[1], int(sys.argv[2])
work = os.environ.get("EDEN_WORK") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "work")
os.chdir(os.path.join(work, "shots"))
os.makedirs("/tmp/cmp", exist_ok=True)
fs = sorted(glob.glob(f"r{r}_*.png"), key=lambda f: int(f.split("_")[1][:-5]))[::p]
for k in range(0, len(fs), 63):
    g = fs[k:k+63]; im = Image.new("RGB", (9*256, ((len(g)+8)//9)*154))
    for i, f in enumerate(g):
        t = Image.open(f).convert("RGB").resize((256, 144)); ImageDraw.Draw(t).text((4, 4), f.split("_")[1][:-4], fill=(255, 255, 0)); im.paste(t, ((i % 9)*256, (i//9)*154))
    im.save(f"/tmp/cmp/m{r}_{k//63}.jpg", quality=80)
print(len(fs))
