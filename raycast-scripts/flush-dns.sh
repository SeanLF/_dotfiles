#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Flush DNS Cache
# @raycast.mode compact
# Optional parameters:
# @raycast.icon globe
# @raycast.packageName Network

# -n: the sudoers rule from setup.sh dns makes these two passwordless; anything
# else should fail rather than hang on a prompt Raycast can't show.
sudo -n dscacheutil -flushcache && sudo -n killall -HUP mDNSResponder && echo "DNS cache flushed"
