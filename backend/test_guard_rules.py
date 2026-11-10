"""Firewall policy rendering only: never invokes nft or changes host networking."""
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('linux_guard',Path(__file__).parents[1]/'native/guard/linux_guard.py')
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
class GuardRulesTests(unittest.TestCase):
    def test_drop_both_families_without_established_escape(self):
        body=guard.rules('fwvless0')
        self.assertIn('table inet foxway_guard',body)
        self.assertIn('policy drop',body)
        self.assertIn('meta mark 18007 accept',body)
        self.assertNotIn('ct state established',body)
        self.assertNotIn('flush ruleset',body)
    def test_atomic_replacement_only_own_table(self):
        self.assertTrue(guard.rules('fw0123456789',True).startswith('delete table inet foxway_guard\n'))
    def test_untrusted_interface_cannot_inject_firewall_commands(self):
        for name in ('eth0','tun0','fwvless0"; flush ruleset','fw../../etc'):
            with self.assertRaises(ValueError):guard.rules(name)
