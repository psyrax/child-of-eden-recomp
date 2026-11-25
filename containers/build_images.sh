#!/bin/bash
# Builds the container images in dependency order. Run from anywhere; the build context is the repo root.
# Idempotent: an image that already exists is skipped unless --rebuild is given.
#   containers/build_images.sh               build, run, run-audio, run-ffmpeg (build the game and run headless tests)
#   containers/build_images.sh --vr          also build-xr, monado, wivrn (VR fork: OpenXR build, Monado, WiVRn server)
#   containers/build_images.sh --capture     also capture, capture-gamescope (real video recording; they derive from
#                                            wivrn, so monado and wivrn are built too)
#   containers/build_images.sh --experiments also exp-xenonrecomp, exp-rexglue-tool (containers/experiments)
#   --all       everything above          --rebuild   build even if the image exists
#   --dry-run   print the commands without running them
# ENGINE=podman uses Podman instead of Docker.
#
# Dependency chain:  build -> run -> run-audio -> run-ffmpeg -> monado -> wivrn -> capture -> capture-gamescope
#                    build -> build-xr          exp-xenonrecomp -> exp-rexglue-tool
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${ENGINE:-docker}"
VR=0; CAPTURE=0; EXPERIMENTS=0; REBUILD=0; DRY=0
for a in "$@"; do case "$a" in
  --vr) VR=1;;
  --capture) CAPTURE=1;;
  --experiments) EXPERIMENTS=1;;
  --all) VR=1; CAPTURE=1; EXPERIMENTS=1;;
  --rebuild) REBUILD=1;;
  --dry-run) DRY=1;;
  -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "ERROR: unknown option '$a'. Options: --vr --capture --experiments --all --rebuild --dry-run" >&2; exit 2;;
esac; done
command -v "$ENGINE" >/dev/null 2>&1 || [ $DRY = 1 ] || { echo "ERROR: '$ENGINE' not found. Install Docker or Podman, or set ENGINE=<engine>." >&2; exit 1; }

# build_image <tag> <file relative to the repo root> [<context relative to the repo root>]
build_image() {
  local tag=$1 file=$2 ctx=${3:-.}
  if [ $REBUILD = 0 ] && [ $DRY = 0 ] && "$ENGINE" image inspect "eden-recomp:$tag" >/dev/null 2>&1; then
    echo "== eden-recomp:$tag already exists; skipped (use --rebuild to build it again)"; return 0
  fi
  if [ $REBUILD = 0 ] && [ $DRY = 1 ] && command -v "$ENGINE" >/dev/null 2>&1 && "$ENGINE" image inspect "eden-recomp:$tag" >/dev/null 2>&1; then
    echo "# eden-recomp:$tag already exists; would be skipped"; return 0
  fi
  if [ $DRY = 1 ]; then
    echo "$ENGINE build -t eden-recomp:$tag -f $ROOT/$file $ROOT/$ctx"; return 0
  fi
  echo "== building eden-recomp:$tag"
  "$ENGINE" build -t "eden-recomp:$tag" -f "$ROOT/$file" "$ROOT/$ctx" \
    || { echo "ERROR: building eden-recomp:$tag failed. Fix the error above and run this again; the images already built are kept." >&2; exit 1; }
}

build_image build containers/build.Dockerfile
build_image run containers/run.Dockerfile
build_image run-audio containers/run-audio.Dockerfile
build_image run-ffmpeg containers/run-ffmpeg.Dockerfile
if [ $VR = 1 ]; then
  build_image build-xr containers/build-xr.Dockerfile
fi
if [ $VR = 1 ] || [ $CAPTURE = 1 ]; then
  build_image monado containers/monado.Dockerfile
  build_image wivrn containers/wivrn.Dockerfile
fi
if [ $CAPTURE = 1 ]; then
  build_image capture containers/capture.Dockerfile
  build_image capture-gamescope containers/capture-gamescope.Dockerfile
fi
if [ $EXPERIMENTS = 1 ]; then
  build_image exp-xenonrecomp containers/experiments/xenonrecomp.Containerfile containers/experiments
  build_image exp-rexglue-tool containers/experiments/rexglue-tool.Containerfile containers/experiments
fi
echo "done."
