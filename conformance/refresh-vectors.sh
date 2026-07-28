#!/bin/bash
# Pull the conformance vectors from the protocol repository and re-pin them.
#
#   ./refresh-vectors.sh
#
# The vectors are vendored rather than fetched at test time on purpose: this
# harness runs offline by design - no networking, no server emulator - and a
# fresh clone has to work without a network. The cost of vendoring is that a
# copy can quietly stop matching the source, which is what the .sha256 beside
# it is for: run.py checks it before anything else and refuses to run against
# a file that has been edited locally.
#
# What the pin cannot tell you is that the *upstream* file has moved on - no
# offline check can. Run this to find out, and commit the result if it changes.
set -euo pipefail
cd "$(dirname "$0")"

RAW="https://raw.githubusercontent.com/rachel-multiverse/protocol/main/specs/fixtures/rubp-messages-v1.json"

before="$(shasum -a 256 rubp-messages-v1.json | cut -d' ' -f1)"
curl -sfL "$RAW" -o rubp-messages-v1.json
after="$(shasum -a 256 rubp-messages-v1.json | cut -d' ' -f1)"

shasum -a 256 rubp-messages-v1.json > rubp-messages-v1.sha256

if [ "$before" = "$after" ]; then
  echo "vectors already current ($after)"
else
  echo "vectors updated"
  echo "  was $before"
  echo "  now $after"
  echo "commit rubp-messages-v1.json and rubp-messages-v1.sha256 together."
fi
