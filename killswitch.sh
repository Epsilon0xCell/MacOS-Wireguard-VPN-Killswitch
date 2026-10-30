#!/bin/bash

# Define the name of your WireGuard VPN interface.
# Override without editing the file, for example:
#   VPN_INTERFACE=utun4 sudo -E ./killswitch.sh
VPN_INTERFACE="${VPN_INTERFACE:-utun3}"

# The interface name goes into a pf ruleset, so reject anything that is
# not a plain interface name.
if ! [[ "$VPN_INTERFACE" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Error: invalid VPN interface name: $VPN_INTERFACE" >&2
    exit 2
fi

RULES_FILE="$(mktemp /tmp/vpn-killswitch-pf.XXXXXX)" || exit 1
trap 'rm -f "$RULES_FILE"' EXIT

# Load one ruleset that blocks everything except traffic leaving via
# the VPN interface. Each `pfctl -f` load replaces the whole ruleset,
# so the block and the pass rule must be loaded together, in one file.
load_killswitch_rules() {
    printf 'block all\npass out on %s all\n' "$VPN_INTERFACE" > "$RULES_FILE"
    if ! sudo pfctl -f "$RULES_FILE"; then
        echo "Error: failed to load pf rules. Killswitch is NOT active." >&2
        exit 1
    fi
}

load_block_all() {
    echo "block all" > "$RULES_FILE"
    if ! sudo pfctl -f "$RULES_FILE"; then
        echo "Error: failed to load block-all pf rules." >&2
        exit 1
    fi
}

# Load the rules first, then enable pf, so there is no window where pf
# is enabled with no (or a partial) ruleset.
load_killswitch_rules
if ! sudo pfctl -E; then
    echo "Error: failed to enable pf. Killswitch is NOT active." >&2
    exit 1
fi

# Display a message indicating the killswitch is active
echo "VPN Killswitch is active. Only traffic through $VPN_INTERFACE is allowed."

# Monitor the VPN connection status and block traffic when VPN is
# disconnected. Rules are only reloaded when the state changes: on
# disconnect the pass rule is dropped, and on reconnect it is restored
# (previously the pass rule was never restored, so the VPN stayed
# blocked after a reconnect).
vpn_up=""
while true; do
    if ifconfig "$VPN_INTERFACE" &> /dev/null; then
        # VPN interface exists, VPN is connected
        if [ "$vpn_up" = "no" ]; then
            echo "VPN is reconnected. Restoring killswitch rules for $VPN_INTERFACE."
            load_killswitch_rules
        fi
        vpn_up="yes"
        sleep 5
    else
        # VPN interface doesn't exist, VPN is disconnected, block all traffic
        if [ "$vpn_up" != "no" ]; then
            echo "VPN is disconnected. Enforcing killswitch."
            load_block_all
        fi
        vpn_up="no"
        sleep 5
    fi
done
