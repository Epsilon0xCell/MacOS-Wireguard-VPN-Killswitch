#!/bin/bash

# Disable pf to allow normal internet access. Note that this disables
# pf entirely, not just the killswitch rules.
if ! sudo pfctl -d; then
    echo "Error: failed to disable pf. The killswitch may still be active." >&2
    exit 1
fi

# Display a message indicating the killswitch is disabled
echo "VPN Killswitch is disabled. Normal internet access is restored."
