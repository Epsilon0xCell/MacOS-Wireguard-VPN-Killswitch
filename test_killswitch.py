"""Portable checks for the killswitch scripts.

pfctl is macOS only, so the ruleset loading itself cannot run on
this Linux host and I do not claim it did. What runs anywhere is the
part before pf: syntax, help, argument rejection, and the interface
name validation, which exits 2 before any sudo or pfctl call. A
script that reached pfctl on this host would print a pfctl error
instead, so seeing the exit 2 results below is itself the evidence
the validation ran first.
"""

import os
import subprocess
import unittest
import pathlib

HERE = pathlib.Path(__file__).parent
KILLSWITCH = HERE / "killswitch.sh"
UNKILLSWITCH = HERE / "unkillswitch.sh"


def run(script, args=(), env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(script), *args], capture_output=True, text=True, env=env
    )


class PortablePathTests(unittest.TestCase):
    def test_bash_syntax_both_scripts(self):
        for script in (KILLSWITCH, UNKILLSWITCH):
            out = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)

    def test_help_exits_0_and_never_touches_pf(self):
        for script in (KILLSWITCH, UNKILLSWITCH):
            out = run(script, ["--help"])
            self.assertEqual(out.returncode, 0, script.name)
            self.assertIn("Usage:", out.stdout)
            self.assertNotIn("pfctl", out.stderr)

    def test_unknown_argument_exits_2(self):
        for script in (KILLSWITCH, UNKILLSWITCH):
            out = run(script, ["--bogus"])
            self.assertEqual(out.returncode, 2, script.name)

    def test_invalid_interface_name_exits_2(self):
        out = run(KILLSWITCH, env_extra={"VPN_INTERFACE": "bad;rm -rf"})
        self.assertEqual(out.returncode, 2)
        self.assertIn("invalid VPN interface name", out.stderr)

    def test_interface_name_with_space_exits_2(self):
        out = run(KILLSWITCH, env_extra={"VPN_INTERFACE": "utun 3"})
        self.assertEqual(out.returncode, 2)


if __name__ == "__main__":
    unittest.main()
