#!/bin/bash
# Runs INSIDE gamescope (launched by run.sh and friends). Usage: steps.sh <N> <actions...>; action = f<sec> (screenshot), k<sec>:<key> (press for 0.3 s), t<sec>:<key> (instant tap, for menu keys such as F4), d<sec>:<key> (hold), u<sec>:<key> (release), b<start>-<end> (bot), m<sec>:rx,ry,rz,lx,ly,lz (hands of the VR synthetic skeleton, right then left, written to /b/vr_hands.txt)
N=$1; shift
rm -f /b/vr_hands.txt  # do not leave the hands file of a previous run behind (its counter would fire on its own)
# AUDIO=pulseaudio: there is no sound card; PulseAudio with a null sink (it keeps real-time pace) and parec records to /b/audio<N>.wav.
# (ALSA 'file' on top of 'null' does NOT work: with no clock, it wrote 47 GB of silence in 100 s.)
if [ "$SDL_AUDIODRIVER" = pulseaudio ] && [ "$VIDEO" != pw ]; then
  pulseaudio --daemonize=yes --exit-idle-time=-1 --disallow-exit -n --load="module-native-protocol-unix" --load="module-null-sink sink_name=nullsink rate=48000 channels=2" --load="module-always-sink" 2>/tmp/pulse.err
  sleep 1; pactl set-default-sink nullsink
  date +%s.%N > /tmp/audio_start.txt
  timeout 900 parec -d nullsink.monitor --file-format=wav --rate=48000 --channels=2 /b/audio$N.wav &
fi
./eden --title.game_root=/assets --gpu.driver=vulkan --gpu.xenos.allow_invalid_fetch_constants=true --gpu.xenos.readback_memexport=true --gpu.xenos.readback_memexport_lazy=true --gpu.xenos.clear_memory_page_state=false --hid.mnk_mode=true $EDEN_EXTRA > /b/run$N.log 2>&1 &
E=$!
# VIDEO=pw (set by run_video.sh): real video. gamescope publishes its image as a PipeWire node; GStreamer encodes it
# together with the audio of the null sink into /b/video<N>.mkv. Hardware encoder (VA-API) with VIDEO_CODEC=va; otherwise x264.
if [ "$VIDEO" = pw ]; then
  for i in $(seq 1 40); do NODE=$(pw-cli ls Node 2>/dev/null | grep -B6 -i 'node.name = "gamescope"' | grep -o 'id [0-9]*' | head -1 | cut -d' ' -f2); [ -n "$NODE" ] && break; sleep 0.5; done
  echo "gamescope node=$NODE" > /tmp/gst.log
  CODEC="x264enc speed-preset=veryfast bitrate=${VIDEO_KBPS:-12000} key-int-max=120"
  [ "${VIDEO_CODEC:-}" = va ] && CODEC="vah264enc bitrate=${VIDEO_KBPS:-12000}"
  pw-cli info $NODE 2>/dev/null | grep -E "media|format|node.name" >> /tmp/gst.log; pactl list short sources >> /tmp/gst.log 2>&1
    gst-launch-1.0 -e pipewiresrc target-object=gamescope do-timestamp=true ! videoconvert ! videorate ! video/x-raw,format=I420,framerate=${VIDEO_FPS:-60}/1 ! queue max-size-buffers=120 ! $CODEC ! h264parse ! queue ! mux. \
    pulsesrc device=nullsink.monitor do-timestamp=true ! audio/x-raw,rate=48000,channels=2 ! queue ! audioconvert ! opusenc bitrate=160000 ! queue ! mux. \
    matroskamux name=mux ! filesink location=/b/video$N.mkv >> /tmp/gst.log 2>&1 &
  GST=$!
fi
# VIDEO=1 (needs AUDIO=pulseaudio): burst of gamescope screenshots to /b/vf<N>/<epoch>.png; they are joined afterwards with make_video.sh.
# (ffmpeg x11grab does NOT work: the game presents through Vulkan straight to gamescope and the X root comes out black.)
if [ "$VIDEO" = 1 ]; then mkdir -p /b/vf$N; rm -f /b/vf$N/*.png; cp /tmp/audio_start.txt /b/vf$N/audio_start.txt
  ( sleep ${VIDEO_FROM:-1}; while kill -0 $E 2>/dev/null; do gamescopectl screenshot /b/vf$N/$(date +%s.%N).png >/dev/null 2>&1; done ) & fi
wait_until() { while [ $SECONDS -lt $1 ]; do sleep 0.25; done; }
# Dumb bot to get through levels with no player: b<start>-<end>. Sweeps the reticle in a balanced pattern holding A (lock-on
# laser) and, every 5th step, X (rapid fire); releases to shoot; every ~12 s taps B (closes tutorials / uses Euphoria).
bot() { local end=$1 i=0 dirs=(d w a a s d d w a s) k btn
  while [ $SECONDS -lt $end ] && kill -0 $E 2>/dev/null; do k=${dirs[$((i%10))]}; btn=space; [ $((i%5)) = 4 ] && btn=l
    xdotool keydown $btn keydown $k; sleep 0.5; xdotool keyup $k; sleep 0.1; xdotool keyup $btn; i=$((i+1))
    if [ $((i%20)) = 0 ]; then xdotool keydown BackSpace; sleep 0.2; xdotool keyup BackSpace; fi
    if [ -n "$BOT_SHOT" ] && [ $((i%BOT_SHOT)) = 0 ]; then gamescopectl screenshot /c/r${N}_$(printf %04d $SECONDS)s.png >/dev/null 2>&1; fi
  done; }
for a in "$@"; do
  case $a in
    f*) t=${a#f}; wait_until $t; gamescopectl screenshot /c/r${N}_$(printf %03d $t)s.png >/dev/null 2>&1;;
    k*) t=${a#k}; k=${t#*:}; t=${t%%:*}; wait_until $t; xdotool keydown $k; sleep 0.3; xdotool keyup $k; echo "key $t $k rc=$?";;
    d*) t=${a#d}; k=${t#*:}; t=${t%%:*}; wait_until $t; xdotool keydown $k; echo "down $t $k";;
    u*) t=${a#u}; k=${t#*:}; t=${t%%:*}; wait_until $t; xdotool keyup $k; echo "up $t $k";;
    t*) t=${a#t}; k=${t#*:}; t=${t%%:*}; wait_until $t; xdotool key $k; echo "tap $t $k";;
    m*) t=${a#m}; k=${t#*:}; t=${t%%:*}; wait_until $t; echo "${k//,/ }" > /b/vr_hands.tmp; mv /b/vr_hands.tmp /b/vr_hands.txt; echo "hands $t $k";;
    b*) t=${a#b}; wait_until ${t%%-*}; bot ${t#*-}; echo "bot until ${t#*-}";;
  esac
done
sleep 2; kill $E; sleep 2; pkill -INT parec; sleep 1
[ -n "${GST:-}" ] && { kill -INT $GST; for i in $(seq 1 20); do kill -0 $GST 2>/dev/null || break; sleep 0.5; done; }
