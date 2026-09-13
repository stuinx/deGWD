import copy
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
build = runpy.run_path(str(ROOT / 'resource/client/ui-script/ui-NodeSM'))['build_config']
presets = json.loads((ROOT / 'resource/client/ui-web/routing-presets.json').read_text())

class PresetTests(unittest.TestCase):
    def setUp(self):
        self.state = {'v2node': [{'name': 'A', 'domain': 'node.example.com:443', 'uuid': '123e4567-e89b-12d3-a456-426614174000', 'path': '/ws'}],
                      'v2nodeDIV': {'nodeSM': {'netflix': 'old', 'hdh': 'old', 'tvb': 'old', 'bahamut': 'old', 'openai': 'node.example.com:443'}}}
        self.config = {'outbounds': [{'tag': 'default', 'protocol': 'freedom'}, {'tag': 'direct', 'protocol': 'freedom'}, {'tag': 'nodeSMnetflix'}],
                       'routing': {'rules': [{'ip': ['geoip:private'], 'outboundTag': 'direct'}, {'outboundTag': 'nodeSMnetflix'}, {'domain': ['domain:custom.test'], 'outboundTag': 'default'}]}}
        self.choices = {key: 0 for key in presets}

    def test_exact_categories(self):
        self.assertEqual(set(presets), set('youtube openai claude gemini grok wikipedia reddit github discord telegram twitter apple steam'.split()))

    def test_removed_rules_and_saved_choices(self):
        state, config = build(self.state, self.config, presets)
        for key in ('netflix', 'hdh', 'tvb', 'bahamut'):
            self.assertNotIn(key, state['v2nodeDIV']['nodeSM'])
            self.assertNotIn('nodeSM' + key, json.dumps(config))
        self.assertEqual(state['v2nodeDIV']['nodeSM']['openai'], self.state['v2node'][0]['domain'])

    def test_independent_selection_and_defaults(self):
        self.choices['claude'] = 1
        self.choices['reddit'] = 1
        state, config = build(self.state, self.config, presets, self.choices)
        rules = {r.get('ruleTag'): r for r in config['routing']['rules']}
        self.assertEqual(rules['preset-claude']['outboundTag'], 'nodeSMclaude')
        self.assertEqual(rules['preset-reddit']['outboundTag'], 'nodeSMreddit')
        self.assertEqual(rules['preset-gemini']['outboundTag'], 'default')
        self.assertEqual(rules['preset-apple']['outboundTag'], 'direct')
        self.assertEqual(rules['preset-telegram-ip']['outboundTag'], 'default')
        self.assertEqual(config['routing']['rules'][0]['ip'], ['geoip:private'])
        outbound = next(o for o in config['outbounds'] if o['tag'] == 'nodeSMclaude')
        self.assertEqual(outbound['streamSettings']['tlsSettings']['serverName'], 'node.example.com')

    def test_all_defaults_disable_preset_status(self):
        state, _ = build(self.state, self.config, presets, self.choices)
        self.assertEqual(state['v2nodeDIV']['nodeSM']['status'], 'off')

    def test_idempotent_reapply(self):
        first = build(self.state, self.config, presets, self.choices)
        self.assertEqual(first, build(*first, presets))

    def test_invalid_selection_does_not_mutate_input(self):
        old_state, old_config = copy.deepcopy(self.state), copy.deepcopy(self.config)
        for invalid in (-1, 2, '1', True):
            self.choices['claude'] = invalid
            with self.assertRaises(ValueError):
                build(self.state, self.config, presets, self.choices)
        self.assertEqual(self.state, old_state)
        self.assertEqual(self.config, old_config)

    def test_deleted_node_falls_back(self):
        self.state['v2nodeDIV']['nodeSM']['claude'] = 'deleted.example'
        state, config = build(self.state, self.config, presets)
        rule = next(r for r in config['routing']['rules'] if r.get('ruleTag') == 'preset-claude')
        self.assertEqual(rule['outboundTag'], 'default')
        self.assertNotIn('claude', state['v2nodeDIV']['nodeSM'])

    def test_grok_and_twitter_do_not_overlap(self):
        self.assertFalse(set(presets['grok']['domains']) & set(presets['twitter']['domains']))
        self.assertNotIn('domain:google.com', presets['gemini']['domains'])

    def test_missing_default_is_rejected(self):
        self.config['outbounds'] = [{'tag': 'direct'}]
        with self.assertRaises(ValueError):
            build(self.state, self.config, presets, self.choices)

if __name__ == '__main__':
    unittest.main()
