#!/usr/bin/env bash
# Re-assert keyboard focus on the window focused before the tools toolbar
# grabbed the keyboard. Delegates to the shared bounce-refocus helper.
exec "$(dirname "$0")/refocus-prev.sh" /tmp/qs-tools-prevwin
