# Real video recording of test runs: gamescope publishes its image through PipeWire and GStreamer encodes it together
# with the audio. Ubuntu packages only.
# Build (from the repo root): docker build -t eden-recomp:capture -f containers/capture.Dockerfile .
FROM eden-recomp:wivrn
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    gstreamer1.0-tools gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-pulseaudio ffmpeg xdotool \
 && rm -rf /var/lib/apt/lists/*
