"""Validate the supplied profile; never print certificate or profile contents."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

temp = Path(os.environ['RUNNER_TEMP'])
marker = temp / 'rustdesk-installed-profile'
profiles = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
if '--clean' in sys.argv:
    if marker.exists():
        name = marker.read_text()
        if re.fullmatch(r'[A-Fa-f0-9-]+\.mobileprovision', name):
            (profiles / name).unlink(missing_ok=True)
        marker.unlink()
    for name in ('ios-profile.mobileprovision', 'ios-profile.plist', 'ExportOptions.plist'):
        (temp / name).unlink(missing_ok=True)
    sys.exit(0)
with (temp / 'ios-profile.plist').open('rb') as f:
    profile = plistlib.load(f)
bundle = os.environ['IOS_BUNDLE_ID']
team = os.environ['APPLE_TEAM_ID']
mode = os.environ['SIGNING_MODE']
uuid = profile['UUID']
if not re.fullmatch(r'[A-Fa-f0-9-]+', uuid):
    raise SystemExit('Invalid provisioning profile UUID')
if team not in profile.get('TeamIdentifier', []):
    raise SystemExit('Provisioning profile belongs to a different team')
identifier = profile.get('Entitlements', {}).get('application-identifier', '')
if identifier != f'{team}.{bundle}':
    raise SystemExit('Use an explicit provisioning profile matching IOS_BUNDLE_ID')
profiles.mkdir(parents=True, exist_ok=True)
name = f'{uuid}.mobileprovision'
shutil.copyfile(temp / 'ios-profile.mobileprovision', profiles / name)
marker.write_text(name)
options = {'method': mode, 'teamID': team, 'signingStyle': 'manual',
           'provisioningProfiles': {bundle: uuid}, 'manageAppVersionAndBuildNumber': False}
with (temp / 'ExportOptions.plist').open('wb') as f:
    plistlib.dump(options, f)
# CocoaPods already supplies xcodeproj; apply signing only to the app target.
subprocess.run(['ruby', '-rxcodeproj', '-e', '''
p = Xcodeproj::Project.open('flutter/ios/Runner.xcodeproj')
p.targets.select { |t| t.name == 'Runner' }.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('APPLE_TEAM_ID')
    config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
    config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = ARGV[0]
    config.build_settings['CODE_SIGN_IDENTITY'] = ENV['SIGNING_MODE'] == 'development' ? 'Apple Development' : 'Apple Distribution'
  end
end
p.save
''', uuid], check=True)
