#!/usr/bin/env python3
"""Refresh the app's bundled fallback from a published CF23 Data snapshot."""
import argparse
import hashlib
import json
from pathlib import Path

from fetch_creator_data import BASE_URL, read_json, resolve

DATA_DIR = Path(__file__).resolve().parent.parent / 'data'


def validate(snapshot: dict) -> None:
    if type(snapshot.get('version')) is not int or snapshot['version'] < 1:
        raise ValueError('Invalid map snapshot version')
    layout = snapshot['layout']
    if isinstance(layout, dict):
        if layout.get('schemaVersion') != 2 or not layout.get('features'):
            raise ValueError('Unsupported or empty map layout')
    elif not isinstance(layout, list) or not layout:
        raise ValueError('Unsupported or empty map layout')
    proximity = snapshot['proximity']
    if proximity.get('schema_version') != 1:
        raise ValueError('Unsupported booth proximity schema')
    layout_bytes = json.dumps(layout, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    if hashlib.sha256(layout_bytes).hexdigest() != proximity.get('map_sha256'):
        raise ValueError('Map and booth proximity do not match')
    if len(proximity['booths']) != len(proximity['neighbors']):
        raise ValueError('Invalid booth proximity table')


def refresh(source: str, destination: Path = DATA_DIR) -> None:
    descriptor = read_json(resolve(source, 'manifest.json'))['map']
    snapshot = read_json(resolve(source, descriptor['path']))
    validate(snapshot)
    if snapshot['version'] != descriptor['version']:
        raise ValueError('Map version does not match manifest')
    # Validate the entire download before replacing any fallback files.
    for name, document in (
        ('map.json', snapshot['layout']),
        ('booth-proximity.json', snapshot['proximity']),
        ('map-version.json', {'version': snapshot['version']}),
    ):
        (destination / name).write_text(
            json.dumps(document, ensure_ascii=False, separators=(',', ':')) + '\n',
            encoding='utf-8', newline='\n')
    print(f"Bundled map updated to version {snapshot['version']}")


def check(destination: Path = DATA_DIR) -> None:
    validate({
        **json.loads((destination / 'map-version.json').read_bytes()),
        'layout': json.loads((destination / 'map.json').read_bytes()),
        'proximity': json.loads((destination / 'booth-proximity.json').read_bytes()),
    })
    print('Bundled map and proximity match')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default=BASE_URL,
                        help='Site base URL or local cf23-data/public directory')
    parser.add_argument('--check', action='store_true',
                        help='Validate bundled files offline without downloading')
    args = parser.parse_args()
    if args.check:
        check()
    else:
        refresh(args.source)
