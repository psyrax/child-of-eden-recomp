# Runtime image for headless test runs: eden-recomp:build + gamescope, weston, Xwayland, screenshot and X11 tools,
# ImageMagick and xdotool.
# Build (from the repo root): docker build -t eden-recomp:run -f containers/run.Dockerfile .
FROM eden-recomp:build
USER root
RUN apt-get update && apt-get install -y --no-install-recommends gamescope weston xwayland grim vulkan-tools x11-apps imagemagick x11-utils xdotool && rm -rf /var/lib/apt/lists/*
