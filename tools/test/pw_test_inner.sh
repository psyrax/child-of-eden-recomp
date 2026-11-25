#!/bin/bash
# Runs INSIDE gamescope (image eden-recomp:capture, launched by pw_test.sh), with vkcube instead of the game: tests the
# PipeWire capture. Usage: pw_test_inner.sh <tag> <pipewiresrc element with its properties>
TAG=$1; shift
vkcube > /tmp/vkcube.log 2>&1 &
V=$!
sleep 3
{ echo "== nodes"; pw-cli ls Node 2>&1 | grep -E "^\s*id |node.name|media.class|object.serial"
  echo "== ports"; pw-link -o 2>&1; pw-link -i 2>&1
  echo "== gst: $*"; } > /b/pw_$TAG.log
rm -f /b/pw_$TAG.mkv
( sleep 7; { echo "== at 7 s: links"; pw-link -l; pw-dump | python3 /s/test/pw_summary.py; [ -n "$STACK" ] && { echo "== gamescope threads"; G=$(pgrep -o -f "^gamescope --backend"); for t in /proc/$G/task/*; do echo "$(cat $t/comm) $(cut -d" " -f3,14,15 $t/stat) $(grep -E "^(voluntary|nonvol)" $t/status | tr "\n\t" "  ")"; done; getcap $(which gamescope) 2>&1; echo "== gamescope stacks"; gdb -p $(pgrep -o -f "^gamescope --backend") -batch -ex "thread apply all bt 14" 2>&1 | grep -v -E "^\[New|^warning"; }; } > /b/pw_$TAG.mid 2>&1 ) &
GST_DEBUG=${GST_DEBUG:-pipewiresrc:4} timeout -s INT ${DUR:-12} gst-launch-1.0 -e $* ! videoconvert ! videorate ! video/x-raw,format=I420,framerate=60/1 ! x264enc speed-preset=ultrafast ! matroskamux ! filesink location=/b/pw_$TAG.mkv >> /b/pw_$TAG.log 2>&1
echo "== gst rc=$?" >> /b/pw_$TAG.log
{ echo "== links"; pw-link -l 2>&1; echo "== wireplumber"; tail -20 /tmp/wireplumber.log; } >> /b/pw_$TAG.log
kill $V
