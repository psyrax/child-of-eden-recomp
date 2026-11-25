# Stage 3 of the VR fork: Monado (open-source OpenXR runtime, Ubuntu 26.04 package) with its simulated headset, and the OpenXR SDK.
# Build (from the repo root): docker build -t eden-recomp:monado -f containers/monado.Dockerfile .
FROM eden-recomp:run-ffmpeg
USER root
RUN apt-get update && apt-get install -y --no-install-recommends monado-service libopenxr1-monado monado-cli libopenxr-dev libopenxr-loader1 libopenxr-utils openxr-layer-corevalidation && rm -rf /var/lib/apt/lists/*
