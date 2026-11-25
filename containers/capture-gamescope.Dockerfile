# eden-recomp:capture + gamescope 3.16.20 (Ubuntu 26.04 source package) rebuilt with
# patches/gamescope/gamescope-pipewire-enter.patch.
# Reason: with PipeWire 1.6 the gamescope-pw thread blocks (it iterates the loop without pw_loop_enter) and the PipeWire
# capture never delivers frames. Default image of tools/test/run_video.sh.
# Build (from the repo root): docker build -t eden-recomp:capture-gamescope -f containers/capture-gamescope.Dockerfile .
FROM eden-recomp:capture
USER root
COPY patches/gamescope/gamescope-pipewire-enter.patch /tmp/
RUN sed -i "s/^Types: deb$/Types: deb deb-src/" /etc/apt/sources.list.d/ubuntu.sources && apt-get update \
 && apt-get install -y --no-install-recommends dpkg-dev devscripts equivs fakeroot \
 && mkdir /tmp/gs && cd /tmp/gs && apt-get source gamescope=3.16.20+ds-1 \
 && echo "a27984fdab2bbfe353efc772de214ae88cccab07c4507747ed4b7f063b2faa0e  gamescope_3.16.20+ds.orig.tar.xz" | sha256sum -c \
 && apt-get build-dep -y --no-install-recommends gamescope \
 && cd gamescope-3.16.20*/ && patch -p1 < /tmp/gamescope-pipewire-enter.patch \
 && CC=gcc CXX=g++ DEB_BUILD_OPTIONS="nocheck parallel=6" dpkg-buildpackage -b -uc -us \
 && dpkg -i ../gamescope_*.deb && cd / && rm -rf /tmp/gs /var/lib/apt/lists/*
