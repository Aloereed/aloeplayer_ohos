"""Linux path/signing/plugin preparation matching the Windows build pipeline."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
from urllib.parse import unquote, urljoin, urlparse
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def profile(config):
    source = ROOT / f"ohos/build-profile.json5.{config}"
    text = source.read_text(encoding="utf-8-sig")
    def replace(match):
        old = json.loads(match[2]).replace("\\", "/")
        path = ROOT / ".signing" / config / old.rsplit("/", 1)[-1]
        if not path.is_file():
            raise FileNotFoundError(path)
        return match[1] + json.dumps(str(path), ensure_ascii=False)
    text = re.sub(r'("(?:certpath|profile|storeFile)"\s*:\s*)("(?:[^"\\]|\\.)*")', replace, text)
    (ROOT / "ohos/build-profile.json5").write_text(text)
    version = re.search(r"^version:\s*(\S+)\+(\d+)", (ROOT/"pubspec.yaml").read_text(), re.M)
    props = {"hwsdk.dir": os.environ["DEVECO_SDK_HOME"], "flutter.sdk": os.environ["FLUTTER_ROOT"],
             "nodejs.dir": os.environ["DEVECO_NODE_HOME"], "flutter.versionName": version[1], "flutter.versionCode": version[2]}
    (ROOT/"ohos/local.properties").write_text("".join(f"{k}={v}\n" for k,v in props.items()))
    print(f"Prepared Linux {config} signing profile (credentials omitted).")


def plugins():
    config_path = ROOT/".dart_tool/package_config.json"
    packages = json.loads(config_path.read_text())["packages"]
    media = next(p for p in packages if p["name"] == "media_kit")
    media_path = Path(unquote(urlparse(urljoin(config_path.as_uri(), media["rootUri"])).path))
    player = media_path/"lib/src/player/native/player/real.dart"
    text = player.read_text()
    unsafe = """      Initializer(mpv).dispose(ctx);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
      });"""
    safe = """      // Keep queued Dart callbacks valid until mpv terminates.
      mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
        Initializer(mpv).dispose(ctx);
      });"""
    if unsafe in text:
        player.write_text(text.replace(unsafe, safe))
    meta_path = ROOT/".flutter-plugins-dependencies"
    metadata = json.loads(meta_path.read_text())
    stage = ROOT/".dart_tool/ohos-plugins"
    for plugin in metadata["plugins"].get("ohos", []):
        source = Path(plugin["path"]).resolve()
        if not (source/"ohos").is_dir():
            raise FileNotFoundError(source/"ohos")
        if "pub-cache" in str(source) and not source.is_relative_to(stage):
            destination = stage/plugin["name"]
            if not destination.resolve().is_relative_to(stage.resolve()):
                raise ValueError("Invalid plugin staging path")
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source/"ohos", destination/"ohos", ignore=shutil.ignore_patterns("oh_modules", "build", ".hvigor", "node_modules", ".cxx"))
            if plugin["name"] == "video_thumbnail_ohos":
                shutil.copy2(ROOT/"tool/ohos_patches/VideoThumbnailOhosPlugin.ets", destination/"ohos/src/main/ets/components/plugin/VideoThumbnailOhosPlugin.ets")
            plugin["path"] = str(destination)+"/"
        else:
            plugin["path"] = str(source)+"/"
    meta_path.write_text(json.dumps(metadata, separators=(",", ":")))
    print("Prepared OHOS plugin paths and media_kit disposal patch.")


def mpv():
    path = ROOT/"ohos/entry/src/main/cpp/thirdparty/mpv/arm64-v8a/lib/libmpv.so"
    data = path.read_bytes()
    checksum = hashlib.sha256(data).hexdigest()
    original = "daecefe473819a40efc795d2e0cf6916be2c830bc39cb9ccf4251f4c67194d63"
    repaired = "7438fcc2aac0e0bbf2f7ed7f04c286efd2a06bc5bcb8c2212a3123fca1f1dff5"
    accepted = {repaired, "0e566eaa73a04cbf7bbb3aad6f3b6e51096a4f00fd13028a06a3286ce8d665d8", "672e98d497199a89e20893979ecec686dee1113bbe1b609c9a9266aa1679bd32"}
    if checksum == original:
        data = bytearray(data)
        for offset in (0x26922dc, 0x2693144):
            assert struct.unpack_from("<I", data, offset)[0] == 20
            data[offset] = 4
        assert hashlib.sha256(data).hexdigest() == repaired
        path.write_bytes(data)
    elif checksum not in accepted:
        raise ValueError(f"Unknown MPV SHA-256: {checksum}; refusing to patch")
    print("Verified MPV SHA-256:", hashlib.sha256(path.read_bytes()).hexdigest())


def verify(kind, config, started):
    if kind == "hap":
        paths = [ROOT/"ohos/entry/build/default/outputs/default/entry-default-unsigned.hap"]
    else:
        paths = list((ROOT/"ohos/build").rglob("*.app"))
    paths = [p for p in paths if p.is_file() and p.stat().st_mtime >= int(started)]
    if not paths:
        raise RuntimeError("No fresh canonical build output")
    output = ROOT/"output/linux"/f"{kind}-{config}"
    output.mkdir(parents=True, exist_ok=True)
    if kind == "hap":
        paths += [p for p in paths[0].parent.glob("*.hap") if p not in paths and p.stat().st_mtime >= int(started)]
    for path in paths:
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
        shutil.copy2(path, output/path.name)
        print("VERIFIED", path, "bytes", path.stat().st_size, "mtime", path.stat().st_mtime)


if __name__ == "__main__":
    {"profile": profile, "plugins": plugins, "mpv": mpv, "verify": verify}[sys.argv[1]](*sys.argv[2:])
