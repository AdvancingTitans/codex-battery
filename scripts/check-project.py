#!/usr/bin/env python3
"""Check local README links, language keys/placeholders and release metadata (stdlib only)."""
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse

root = pathlib.Path(__file__).resolve().parents[1]
errors = []
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    errors.append('Invalid VERSION')
translations = {}
for language in ('en', 'zh-Hans', 'ja'):
    file = root / 'Resources' / f'{language}.lproj' / 'Localizable.strings'
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(file)], capture_output=True, text=True, check=True)
    translations[language] = json.loads(result.stdout)
keys = translations['en'].keys()
for language, values in translations.items():
    if values.keys() != keys:
        errors.append(f'{language}: localization key mismatch')
    for key in keys:
        placeholders = lambda text: sorted(re.findall(r'%(?:\d+\$)?[@dif]|%%', text))
        if placeholders(values.get(key, '')) != placeholders(key):
            errors.append(f'{language}: format mismatch: {key!r}')
# Require every literal localization call to have a shipped translation.
source = (root / 'CodexBattery.swift').read_text()
for key in re.findall(r'\bL\(("(?:[^"\\]|\\.)*")', source):
    if json.loads(key) not in keys:
        errors.append(f'Missing translated key: {key}')
for file in root.rglob('*.md'):
    if any(part in ('.git', '.build', 'dist') for part in file.relative_to(root).parts):
        continue
    text = file.read_text()
    if file.name.startswith('README'):
        if len(text.splitlines()) > 250:
            errors.append(f'{file.name}: README exceeds budget')
        if '<p align="center">[English]' in text:
            errors.append(f'{file.name}: Markdown links inside raw HTML will not render')
        if f'/releases/download/v{version}/' not in text:
            errors.append(f'{file.name}: exact release download is missing')
    links = re.findall(r'\]\(([^)]+)\)|(?:src|href)="([^"]+)"', text)
    for match in links:
        target = next(part for part in match if part).strip('<>')
        parsed = urllib.parse.urlsplit(target)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        destination = file.parent / urllib.parse.unquote(parsed.path)
        if not destination.exists():
            errors.append(f'{file.relative_to(root)}: missing local target {target}')
for file in root.rglob('*'):
    if not file.is_file() or any(part in ('.git', '.build', 'dist') for part in file.relative_to(root).parts):
        continue
    if file.suffix in ('.md', '.swift', '.sh', '.yml', '.py', '.strings'):
        if re.search(r'/Users/[A-Za-z0-9_-]+/', file.read_text()):
            errors.append(f'{file.relative_to(root)}: machine-specific home path')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(keys)} keys across 3 languages; README links; release version; portable source')
