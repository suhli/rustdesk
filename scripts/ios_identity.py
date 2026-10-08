"""Apply a fork identity only to the iOS build workspace."""
import os
from pathlib import Path
import plistlib
import re

bundle = os.environ.get('IOS_BUNDLE_ID', 'org.rustdesk.enhanced.ios')
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}', bundle):
    raise SystemExit('IOS_BUNDLE_ID must be a reverse-DNS identifier')
if bundle.startswith('com.carriez.'):
    raise SystemExit('Choose an independent fork Bundle ID')
project = Path('flutter/ios/Runner.xcodeproj/project.pbxproj')
project.write_text(re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;',
    f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};', project.read_text()))
info = Path('flutter/ios/Runner/Info.plist')
with info.open('rb') as f:
    values = plistlib.load(f)
values['CFBundleDisplayName'] = 'RustDesk Enhanced'
values['CFBundleName'] = 'RustDesk Enhanced'
for url_type in values.get('CFBundleURLTypes', []):
    url_type['CFBundleURLName'] = bundle
with info.open('wb') as f:
    plistlib.dump(values, f, sort_keys=False)
