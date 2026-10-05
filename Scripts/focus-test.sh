#!/bin/sh
# Milestone 2 gate: opens a TextEdit document, puts the cursor in it, and asks Murmur to click its Flow
# Bar 50 times while checking that TextEdit keeps focus. Hands off the mouse and keyboard for ~40 s.
# The result is written to ~/Library/Application Support/Murmur/focus-test-*.txt.
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null
sleep 1.5
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.swaritsheel.Murmur.debug.runFocusTest"), object: nil, userInfo: nil, deliverImmediately: true)'
echo "Focus test started; waiting for the result…"
before=$(ls "$HOME/Library/Application Support/Murmur"/focus-test-*.txt 2>/dev/null | wc -l)
for i in $(seq 1 90); do
  sleep 1
  now=$(ls "$HOME/Library/Application Support/Murmur"/focus-test-*.txt 2>/dev/null | wc -l)
  if [ "$now" -gt "$before" ]; then cat "$(ls -t "$HOME/Library/Application Support/Murmur"/focus-test-*.txt | head -1)"; exit 0; fi
done
echo "No result after 90 s."; exit 1
