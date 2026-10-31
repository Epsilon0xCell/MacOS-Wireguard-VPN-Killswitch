#!/bin/bash

# Arguments are answered before anything touches pf. The first
# version had no argument handling at all, so running it with
# --help started loading rulesets: help became a state change.
# Unknown arguments exit 2 like the invalid interface name below,
# so a wrapping script can tell bad input from a pfctl failure.
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: [VPN_INTERFACE=utun4] sudo -E ./killswitch.sh"
    echo "Loads a pf ruleset that only allows traffic out via the VPN interface,"
    echo "then watches the interface and drops the pass rule while it is down."
    echo "Run unkillswitch.sh to disable pf again. Takes no arguments."
    exit 0
fi
if [ $# -gt 0 ]; then
    echo "Error: this script takes no arguments (got: $1)" >&2
    exit 2
fi

# Define the name of your WireGuard VPN interface.
# Override without editing the file, for example:
#   VPN_INTERFACE=utun4 sudo -E ./killswitch.sh
# I default to utun3 because that is the interface WireGuard gave me on
# my machine. The -E in the example matters: plain sudo strips the
# caller's environment, so without it this line never sees an override
# and the script silently runs with utun3.
VPN_INTERFACE="${VPN_INTERFACE:-utun3}"

# The interface name goes into a pf ruleset, so reject anything that is
# not a plain interface name.
# I check the shape only, not whether the interface exists. A well
# formed but wrong name passes here and shows up later as a VPN that
# looks permanently down to the monitor loop. Exit 2 is mine for this
# case, so bad input reads differently from a pfctl failure (exit 1)
# in any script that wraps this one.
if ! [[ "$VPN_INTERFACE" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "Error: invalid VPN interface name: $VPN_INTERFACE" >&2
    exit 2
fi

RULES_FILE="$(mktemp /tmp/vpn-killswitch-pf.XXXXXX)" || exit 1
# This trap only deletes the temp file. It does not touch pf, so when
# the script stops, by Ctrl-C or any other way, the last ruleset I
# loaded stays in force until unkillswitch.sh runs. If the script is
# killed with SIGKILL the trap never runs and the temp file is left
# behind in /tmp, which is untidy and nothing worse.
trap 'rm -f "$RULES_FILE"' EXIT

# Load one ruleset that blocks everything except traffic leaving via
# the VPN interface. Each `pfctl -f` load replaces the whole ruleset,
# so the block and the pass rule must be loaded together, in one file.
load_killswitch_rules() {
    # I rewrite the whole file with printf on every load instead of
    # appending, so a block only ruleset left over from a disconnect
    # can never linger as a stale third line in this load.
    printf 'block all\npass out on %s all\n' "$VPN_INTERFACE" > "$RULES_FILE"
    # These functions run in the main shell, not a subshell, so this
    # exit ends the whole script, monitor loop included. If a load
    # fails on reconnect, the block all ruleset from the disconnect is
    # the one still loaded, so the failure lands on the blocked side.
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
# I start vpn_up empty, neither yes nor no, on purpose. The startup
# load above already put the combined ruleset in place, so a first
# poll that finds the interface up must not load it again, and a first
# poll that finds it down must load block all, because the interface
# may have dropped between the startup load and this first check. The
# empty value is what makes both branches do the right thing once.
vpn_up=""
while true; do
    # Existence is all I test. An interface that exists with a dead
    # tunnel behind it still counts as up here, because ifconfig
    # cannot tell me whether traffic would actually reach the peer.
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
