#!/bin/bash

# Might as well ask for password up-front, right?
sudo -v

# Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
while true; do sudo -n true; echo "$(date)" >> /tmp/keep.log.$$ ; sleep 60; kill -0 "$$" || exit; done 2>>/tmp/keep.log.$$ &

# Example: do stuff over the next 30+ mins that requires sudo here or there.
function wait()
{
  echo -n "["; for i in {1..60}; do sleep $1; echo -n =; done; echo "]"
}

wait 0 # show reference bar
echo "$(sudo whoami) | $(date)"
wait 1
echo "$(sudo whoami) | $(date)"
wait 2
echo "$(sudo whoami) | $(date)"
wait 5
echo "$(sudo whoami) | $(date)"
wait 10
echo "$(sudo whoami) | $(date)"
wait 15
echo "$(sudo whoami) | $(date)"
wait 1
sudo -K
echo "$(whoami) | $(date)"
wait 2
echo "$(whoami) | $(date)"
wait 5
echo "done."
