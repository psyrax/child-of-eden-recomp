# Stage 4 of the VR fork: dependencies to build and run the WiVRn server (OpenXR on top of Monado, streams to the Meta Quest 2).
# Ubuntu packages only; WiVRn and its Monado are built from source with tools/build/build_wivrn.sh.
# Build (from the repo root): docker build -t eden-recomp:wivrn -f containers/wivrn.Dockerfile .
FROM eden-recomp:monado
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git patch ca-certificates cmake ninja-build pkg-config g++ gettext xz-utils unzip glslang-tools \
    libavahi-client-dev libavahi-glib-dev libavcodec-dev libavfilter-dev libavutil-dev libswscale-dev libbsd-dev \
    libboost-all-dev libcap-dev libcjson-dev libcli11-dev libeigen3-dev libgl-dev libgl1-mesa-dev libglu1-mesa-dev libglx-dev \
    libnotify-dev libpipewire-0.3-dev libsystemd-dev libudev-dev libva-dev libdrm-dev libvulkan-dev libwayland-dev \
    libx11-xcb-dev libx264-dev libxcb-randr0-dev libxrandr-dev mesa-common-dev nlohmann-json3-dev librsvg2-dev \
    libarchive-dev libpng-dev libssl-dev libusb-1.0-0-dev libhidapi-dev libopenxr-dev python3 \
    mesa-va-drivers vainfo iproute2 pipewire pipewire-pulse wireplumber pulseaudio-utils dbus dbus-daemon \
 && rm -rf /var/lib/apt/lists/*
