"""Verify the actual release APP, including nested HAP version and MPV runtime."""
import io
import json
import sys
import zipfile
from pathlib import Path
from test_mpv_timing_patch import LIB, loaded_sections, driver_caps

app = Path(sys.argv[1])
version, code = sys.argv[2].split('+')
with zipfile.ZipFile(app) as archive:
    haps = [name for name in archive.namelist() if name.endswith('.hap')]
    assert haps, 'APP has no HAP'
    verified_entry = False
    for name in haps:
        with zipfile.ZipFile(io.BytesIO(archive.read(name))) as hap:
            module = json.loads(hap.read('module.json'))
            assert module['app']['versionName'] == version
            assert module['app']['versionCode'] == int(code)
            if module['module']['name'] == 'entry':
                assert 'mqqapi' in module['module']['querySchemes']
                native = hap.read('libs/arm64-v8a/libmpv.so.2')
                assert loaded_sections(native) == loaded_sections(LIB.read_bytes())
                assert driver_caps(native)['ohcodec'] == 4
                assert driver_caps(native)['ohcodec-osd'] == 4
                verified_entry = True
            print(f'PASS {app.name}: {name}, {version}+{code}, QQ scheme and MPV runtime sections')
    assert verified_entry, 'APP has no verified entry module'
