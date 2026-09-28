# Copyright (C) 2026 The mooR Authors
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

"""Prevent false wire-test success from a marker embedded in echoed code."""

import unittest

from wire import Client


class ClosedSocket:
    def recv(self, _limit):
        return b""


class MarkerTests(unittest.TestCase):
    def client(self, received):
        client = Client.__new__(Client)
        client.buffer = received
        client.socket = ClosedSocket()
        return client

    def test_echoed_code_does_not_satisfy_marker(self):
        client = self.client(b'echo: notify(connection(), "WIRE_OK");\r\n')
        with self.assertRaisesRegex(AssertionError, "Connection closed"):
            client.expect_line("WIRE_OK")

    def test_complete_standalone_marker_succeeds(self):
        client = self.client(b'echo: notify(connection(), "WIRE_OK");\r\nWIRE_OK\r\nremaining\r\n')
        self.assertEqual(client.expect_line("WIRE_OK"), "WIRE_OK")
        self.assertEqual(client.buffer, b"remaining\r\n")

    def test_error_trace_containing_marker_is_rejected(self):
        client = self.client(b'Traceback: notify(connection(), "WIRE_OK");\r\nWIRE_OK\r\n')
        with self.assertRaisesRegex(AssertionError, "Unexpected task exception"):
            client.expect_line("WIRE_OK")


if __name__ == "__main__":
    unittest.main()
