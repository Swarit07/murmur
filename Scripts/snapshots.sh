#!/bin/sh
# Asks the running Murmur (Debug menu on) to save PNGs of every Hub page and Flow Bar state to
# ~/Library/Application Support/Murmur/snapshots, for design review.
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.swaritsheel.Murmur.debug.snapshot"), object: nil, userInfo: nil, deliverImmediately: true)'
