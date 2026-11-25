#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman): make_video.sh <N>
#   -> work/build/video<N>.mp4 from work/build/vf<N>/*.png and audio<N>.wav
# The screenshots carry their time (epoch) in the file name: their real duration is kept and the audio is trimmed to match.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
N=$1; B="$WORK/build"
[ -d "$B/vf$N" ] || { echo "$B/vf$N does not exist: first run run.sh with VIDEO=1 AUDIO=pulseaudio"; exit 2; }
n=$(ls "$B/vf$N"/*.png 2>/dev/null | wc -l); [ "$n" -ge 10 ] || { echo "Only $n screenshots in vf$N: nothing to assemble"; exit 2; }
$ENGINE run --rm --user $(id -u):$(id -g) -m 6g --cpus 4 -v "$B:/b" -w /b eden-recomp:run-ffmpeg bash -c "
python3 -I - <<PY
import os
d='/b/vf$N'; fs=sorted(f for f in os.listdir(d) if f.endswith('.png') and os.path.getsize(d+'/'+f)>1000)
t=[float(f[:-4]) for f in fs]; a=float(open(d+'/audio_start.txt').read())
with open(d+'/list.txt','w') as o:
    o.write('ffconcat version 1.0\n')
    for i,f in enumerate(fs):
        o.write('file %s\nduration %.4f\n'%(f,(t[i+1]-t[i]) if i+1<len(fs) else 0.05))
open(d+'/offset.txt','w').write('%.3f'%(t[0]-a))
print('screenshots',len(fs),'duration_s',round(t[-1]-t[0],1),'mean_fps',round(len(fs)/(t[-1]-t[0]),1),'audio_offset_s',round(t[0]-a,2))
PY
ffmpeg -loglevel error -y -f concat -safe 0 -i /b/vf$N/list.txt -ss \$(cat /b/vf$N/offset.txt) -i /b/audio$N.wav -vf fps=30 -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest /b/video$N.mp4
ffprobe -v error -show_entries format=duration,size -of csv=p=0 /b/video$N.mp4"
