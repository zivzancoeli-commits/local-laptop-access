#!/bin/bash
# Display + host-cursor helpers for a Sunshine session.
set -euo pipefail
DIR="$HOME/.config/sunshine"

case "${1:-}" in
  start)
    # Same 1440x900 layout, 1x pixels. That cuts encode work without zooming out.
    "$DIR/set-stream-display" apply || true
    # Leave Computer A's cursor in the capture so the stream shows it when A does.
    "$DIR/hide-host-cursor" stop || true
    ;;
  stop)
    "$DIR/hide-host-cursor" stop || true
    "$DIR/set-stream-display" restore || true
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 1
    ;;
esac
