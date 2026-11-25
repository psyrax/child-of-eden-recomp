# Build image (eden-recomp:build) + the OpenXR headers and loader, to build the SDK's headset output.
# Build (from the repo root): docker build -t eden-recomp:build-xr -f containers/build-xr.Dockerfile .
FROM eden-recomp:build
USER root
RUN apt-get update && apt-get install -y --no-install-recommends libopenxr-dev libopenxr-loader1 && rm -rf /var/lib/apt/lists/*
