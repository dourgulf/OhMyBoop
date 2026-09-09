#!/usr/bin/env python3
"""Check both language resource sets through the packaged app's actual worker."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / "dist/OhMyBoop.app/Contents"
source = '{"name":"你好，世界😀"，"n":1}'
offset = len(source[:source.index('，"n"')].encode("utf-16-le")) // 2
with tempfile.TemporaryDirectory(prefix="ohmyboop-localization-") as folder:
    request = Path(folder) / "input.json"
    response = Path(folder) / "output.json"
    for language, expected in [("en", "Chinese comma"), ("zh-Hans", "中文逗号")]:
        assert (app / "Resources" / (language + ".lproj") / "Localizable.strings").exists()
        request.write_text(json.dumps(dict(toolID="FormatJSON", text=source, selectionLocation=0, selectionLength=0, language=language)))
        subprocess.run([str(app / "MacOS/OhMyBoop"), "--script-worker", str(request), str(response)], check=True, timeout=15)
        result = json.loads(response.read_text())
        assert expected in result["error"], result
        assert result["text"] == source and result["errorOffset"] == offset, result
        print(f"{language}: packaged resources, localized error, UTF-16 position and source preservation passed")
