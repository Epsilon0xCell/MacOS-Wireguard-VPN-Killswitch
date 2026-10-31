#!/bin/bash

# Same argument rule as killswitch.sh: help is answered locally and
# never reaches pfctl, and unknown arguments exit 2.
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: sudo ./unkillswitch.sh"
    echo "Disables pf entirely, which lifts the killswitch rules. Takes no arguments."
    exit 0
fi
if [ $# -gt 0 ]; then
    echo "Error: this script takes no arguments (got: $1)" >&2
    exit 2
fi

# Disable pf to allow normal internet access. Note that this disables
# pf entirely, not just the killswitch rules.
# I disable instead of flushing on purpose, and that cuts both ways:
# anyone who had pf rules of their own before the killswitch ran gets
# them switched off too, and the killswitch rules are still loaded
# afterwards, so a later pfctl -E from anything else brings them back.
if ! sudo pfctl -d; then
    echo "Error: failed to disable pf. The killswitch may still be active." >&2
    exit 1
fi

# Display a message indicating the killswitch is disabled
echo "VPN Killswitch is disabled. Normal internet access is restored."
