#!/bin/bash
# Derives Steam library art from YOUR OWN screenshots of a test run. No art is shipped in this repository, and the
# images it produces come from the game: keep them for your own library, do not redistribute them.
# Runs INSIDE the container (image eden-recomp:run-audio, ImageMagick): steam_art.sh <screenshots dir> <N of the run at 2560x1440>
# For example, from the repo root:
#   docker run --rm --user $(id -u):$(id -g) -v "$PWD/work/shots:/c" -v "$PWD/tools:/s:ro" eden-recomp:run-audio bash /s/package/steam_art.sh /c <N>
# Inputs: r<N>_029s.png (dark title, for the logo), r<N>_031s.png (title), r<N>_044s.png (hub), r<N>_052s.png (Archive Select).
# Outputs in <screenshots>/steam/: cover.png 600x900, wide.png 920x430, hero.png 3840x1240, logo.png (transparent), icon.png 256, icon.ico
set -euo pipefail
C=$1; N=$2; O=$C/steam; mkdir -p $O
for t in 029 031 044 052; do [ -f $C/r${N}_${t}s.png ] || { echo "$C/r${N}_${t}s.png is missing: run tools/test/run.sh $N with GS_W=2560 GS_H=1440 and f29 f31 f44 f52"; exit 2; }; done
# Logo: crop of the title on a dark background; the transparency comes from the brightness.
convert $C/r${N}_029s.png -crop 800x350+1460+915 +repage -level 3%,55% $O/_logo_rgb.png
convert $O/_logo_rgb.png -colorspace Gray -level 12%,70% -blur 0x1 $O/_logo_a.png
convert $O/_logo_rgb.png -modulate 120,110 $O/_logo_a.png -alpha off -compose CopyOpacity -composite -trim +repage $O/logo.png
# Background (hero): a band of the hub, without text.
convert $C/r${N}_044s.png -crop 2560x827+0+310 +repage -filter Lanczos -resize 3840x1240! $O/hero.png
# Vertical cover: the tree of the title screen + the logo at the bottom over a gradient.
convert $C/r${N}_031s.png -crop 960x1440+380+0 +repage -resize 600x900! \
  \( -size 600x380 gradient:none-'#000814e6' \) -gravity south -composite \
  \( $O/logo.png -resize 500x \) -gravity south -geometry +0+70 -composite $O/cover.png
# Wide capsule: the hub with Lumi + the logo on the left.
convert $C/r${N}_044s.png -crop 2560x1196+0+120 +repage -resize 920x430! \
  \( $O/logo.png -resize 330x \) -gravity west -geometry +45-95 -composite $O/wide.png
# Icon: the Matrix sphere with Lumi, cropped to a circle.
convert $C/r${N}_052s.png -crop 900x900+826+206 +repage -resize 256x256 \
  \( -size 256x256 xc:none -fill white -draw 'circle 128,128 128,4' \) -alpha off -compose CopyOpacity -composite $O/icon.png
convert $O/icon.png -define icon:auto-resize=256,128,64,48,32,16 $O/icon.ico
rm -f $O/_logo_rgb.png $O/_logo_a.png
identify -format '%f %wx%h %[channels]\n' $O/*.png
