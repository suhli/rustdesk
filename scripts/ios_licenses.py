"""Collect notices for the Go packages actually linked into the iOS archive."""
import json
from pathlib import Path
import subprocess
import sys

source = subprocess.check_output(
    ['go', 'list', '-mod=readonly', '-deps', '-json', './cmd/ios'], encoding='utf-8')
decoder = json.JSONDecoder()
modules = {}
while source.strip():
    package, end = decoder.raw_decode(source.lstrip())
    source = source.lstrip()[end:]
    module = package.get('Module')
    if module and not module.get('Main'):
        modules[module['Path']] = module.get('Replace', module)

go_root = Path(subprocess.check_output(['go', 'env', 'GOROOT'], encoding='utf-8').strip())
sections = [
    'RustDesk\n' + (Path(__file__).resolve().parents[1] / 'LICENCE').read_text(encoding='utf-8'),
    'Go runtime\n' + (go_root / 'LICENSE').read_text(encoding='utf-8'),
]
for name, module in sorted(modules.items()):
    root = Path(module['Dir'])
    notices = sorted({p for pattern in ('LICENSE*', 'LICENCE*', 'COPYING*', 'NOTICE*', 'PATENTS*')
                      for p in root.glob(pattern) if p.is_file()})
    if not notices:
        raise SystemExit(f'Missing dependency license: {name}; inspect before distributing')
    sections.append(f"{name} {module.get('Version', '')}\n" + '\n'.join(
        f'--- {p.name} ---\n{p.read_text(encoding="utf-8")}' for p in notices))

Path(sys.argv[1]).write_text('\n\n'.join(sections), encoding='utf-8')
print(f'Collected notices for Go and {len(modules)} linked modules')
