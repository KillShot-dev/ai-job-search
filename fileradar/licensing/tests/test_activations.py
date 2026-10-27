"""Activation/deactivation state machine: one active Mac at a time."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from serials import generate_serial
from store import OneActiveMacError, SerialDeactivated, SerialNotFound, Store

MAC_A = "hash-of-mac-a-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MAC_B = "hash-of-mac-b-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


class TestActivations(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.tmp.name, "test.db"))
        self.serial = generate_serial()
        self.store.create_serial(self.serial, "buyer@test.local", 800)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_activate_first_mac(self):
        act = self.store.activate(self.serial, MAC_A)
        self.assertEqual(act["status"], "active")
        self.assertEqual(act["machine_hash"], MAC_A)

    def test_second_mac_rejected_while_first_active(self):
        self.store.activate(self.serial, MAC_A)
        with self.assertRaises(OneActiveMacError):
            self.store.activate(self.serial, MAC_B)

    def test_deactivate_then_activate_new_mac(self):
        self.store.activate(self.serial, MAC_A)
        self.assertEqual(self.store.deactivate(self.serial, MAC_A), 1)
        act = self.store.activate(self.serial, MAC_B)
        self.assertEqual(act["machine_hash"], MAC_B)
        # Serial itself stays active through a move.
        self.assertEqual(self.store.get_serial(self.serial)["status"], "active")

    def test_deactivate_without_machine_arg_frees_current(self):
        self.store.activate(self.serial, MAC_A)
        self.assertEqual(self.store.deactivate(self.serial), 1)
        self.store.activate(self.serial, MAC_B)  # must not raise

    def test_same_mac_reactivation_is_idempotent(self):
        first = self.store.activate(self.serial, MAC_A)
        second = self.store.activate(self.serial, MAC_A)
        self.assertEqual(first["id"], second["id"])
        self.assertEqual(len(self.store.list_activations(self.serial)), 1)

    def test_deactivate_unknown_machine_is_noop(self):
        self.store.activate(self.serial, MAC_A)
        self.assertEqual(self.store.deactivate(self.serial, MAC_B), 0)
        # Original activation still active, so B still cannot activate.
        with self.assertRaises(OneActiveMacError):
            self.store.activate(self.serial, MAC_B)

    def test_unknown_serial_errors(self):
        with self.assertRaises(SerialNotFound):
            self.store.activate("FR-AAAA-AAAA-AAAA-AAAB", MAC_A)

    def test_revoked_serial_cannot_activate(self):
        self.store.activate(self.serial, MAC_A)
        self.store.deactivate_serial(self.serial)
        self.assertEqual(self.store.get_serial(self.serial)["status"], "deactivated")
        with self.assertRaises(SerialDeactivated):
            self.store.activate(self.serial, MAC_B)


if __name__ == "__main__":
    unittest.main()
