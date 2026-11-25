# eden-recomp:run-audio + ffmpeg, to assemble videos from screenshot bursts (tools/test/make_video.sh).
# Build (from the repo root): docker build -t eden-recomp:run-ffmpeg -f containers/run-ffmpeg.Dockerfile .
FROM eden-recomp:run-audio
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
