# eden-recomp:run + PulseAudio, to run the game with sound and record it. Default image of tools/test/run.sh.
# Build (from the repo root): docker build -t eden-recomp:run-audio -f containers/run-audio.Dockerfile .
FROM eden-recomp:run
USER root
RUN apt-get update && apt-get install -y --no-install-recommends pulseaudio pulseaudio-utils && rm -rf /var/lib/apt/lists/*
