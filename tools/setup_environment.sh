#!/usr/bin/env bash
# Reproducible Linux x86_64 tooling, kept outside the project checkout.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${FOOD_SORTING_TOOLS_DIR:-$(dirname -- "$project_dir")/garden-table-tools}"
with_android=0
if [[ "${1:-}" == "--android" ]]; then with_android=1; shift; fi
if [[ $# -gt 0 ]]; then echo 'Usage: tools/setup_environment.sh [--android]' >&2; exit 2; fi
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This helper is for Linux x86_64. On other systems install Godot 4.7.2 from godotengine.org and open project.godot.' >&2
  exit 2
fi
command -v python3 >/dev/null
mkdir -p "$tools_dir"
tools_dir="$(cd -- "$tools_dir" && pwd)"
python3 - "$tools_dir" "$with_android" <<'PY'
import hashlib, pathlib, shutil, stat, sys, urllib.request, zipfile
root = pathlib.Path(sys.argv[1]).resolve()
android = sys.argv[2] == '1'
downloads = root / 'downloads'
downloads.mkdir(exist_ok=True)
release = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/'
def download(name, url, digest, algorithm='sha512'):
    dst = downloads / name
    if not dst.exists():
        print('Downloading', name, flush=True)
        tmp = dst.with_suffix(dst.suffix + '.part')
        with urllib.request.urlopen(url, timeout=90) as response, tmp.open('wb') as out:
            shutil.copyfileobj(response, out)
        tmp.replace(dst)
    with dst.open('rb') as f:
        actual = hashlib.file_digest(f, algorithm).hexdigest()
    if actual != digest:
        raise RuntimeError(f'Checksum mismatch: {dst}. Remove this file and retry; verification is required.')
    print('Verified', name, flush=True)
    return dst

def unpack_stripped(archive, target, wanted=None):
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            parts = pathlib.PurePosixPath(info.filename).parts[1:]
            if not parts or info.is_dir() or (wanted and parts[-1] not in wanted):
                continue
            if '..' in parts or pathlib.PurePosixPath(info.filename).is_absolute():
                raise ValueError('Unsafe archive path')
            dst = target.joinpath(*parts)
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(z.read(info))
            mode = info.external_attr >> 16
            if mode:
                dst.chmod(stat.S_IMODE(mode))
engine_name = 'Godot_v4.7.2-stable_linux.x86_64.zip'
engine_zip = download(engine_name, release + engine_name,
    '9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65')
engine = root / 'godot' / 'Godot_v4.7.2-stable_linux.x86_64'
engine.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(engine_zip) as z:
    payload = z.read(engine.name)
    if not engine.exists() or engine.read_bytes() != payload:
        temporary_engine = engine.with_suffix('.new')
        temporary_engine.write_bytes(payload)
        temporary_engine.chmod(0o755)
        temporary_engine.replace(engine)
engine.chmod(0o755)
if android:
    template_name = 'Godot_v4.7.2-stable_export_templates.tpz'
    archive = download(template_name, release + template_name,
        'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079')
    unpack_stripped(archive, root / 'runtime/data/godot/export_templates/4.7.2.stable',
        {'android_debug.apk', 'android_release.apk', 'version.txt'})
    # Checksums published in https://dl.google.com/android/repository/repository2-3.xml.
    # All archives are fetched over verified HTTPS and checked before extraction.
    packages = [
        ('commandlinetools-linux-16111833_latest.zip', 'e025545c62a8e64c7559119566a569fb1dec5f60', 'cmdline-tools/latest'),
        ('platform-tools_r37.0.1-linux.zip', '477254aa5f903c15cf51001717bdf347fb6b53e0', 'platform-tools'),
        ('build-tools_r36.1_linux.zip', '936a0d6bd5ae3e2118a7567dddbc95ff67ed46e9', 'build-tools/36.1.0'),
        ('platform-36_r02.zip', '2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576', 'platforms/android-36'),
    ]
    for name, digest, destination in packages:
        archive = download(name, 'https://dl.google.com/android/repository/' + name, digest, 'sha1')
        unpack_stripped(archive, root / 'android-sdk' / destination)
PY
mkdir -p "$tools_dir/runtime/config/godot" "$tools_dir/runtime/data" "$tools_dir/runtime/cache" "$tools_dir/android-user"
export XDG_CONFIG_HOME="$tools_dir/runtime/config"
export XDG_DATA_HOME="$tools_dir/runtime/data"
export XDG_CACHE_HOME="$tools_dir/runtime/cache"
export ANDROID_HOME="$tools_dir/android-sdk"
export ANDROID_USER_HOME="$tools_dir/android-user"
export GODOT_BIN="$tools_dir/godot/Godot_v4.7.2-stable_linux.x86_64"
if [[ "$with_android" == 1 ]]; then
  if [[ -z "${JAVA_HOME:-}" ]]; then
    if command -v java >/dev/null; then
      JAVA_HOME="$(dirname -- "$(dirname -- "$(readlink -f -- "$(command -v java)")")")"
      export JAVA_HOME
    else
      echo 'Install OpenJDK 17 or 21, set JAVA_HOME, then rerun --android.' >&2; exit 1
    fi
  fi
  if [[ ! -f "$tools_dir/android-debug.keystore" ]]; then
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$tools_dir/android-debug.keystore" \
      -storepass android -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' \
      -keyalg RSA -keysize 2048 -validity 10000 >/dev/null
  fi
  # Keep this helper's editor configuration separate from the user's normal editor.
  python3 - "$tools_dir" "$JAVA_HOME" <<'PY'
import pathlib,sys,json
root=pathlib.Path(sys.argv[1]); java=sys.argv[2]
settings=root/'runtime/config/godot/editor_settings-4.7.tres'
if settings.exists():
    text=settings.read_text()
else:
    text='[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
values={
 'export/android/java_sdk_path':java,
 'export/android/android_sdk_path':str(root/'android-sdk'),
 'export/android/debug_keystore':str(root/'android-debug.keystore'),
 'export/android/debug_keystore_user':'androiddebugkey',
 'export/android/debug_keystore_pass':'android',
}
lines=text.splitlines()
for key,value in values.items():
    entry=key+' = '+json.dumps(value)
    for i,line in enumerate(lines):
        if line.startswith(key+' ='):
            lines[i]=entry;break
    else:lines.append(entry)
settings.write_text('\n'.join(lines)+'\n')
PY
fi
# Quote all generated paths for safe sourcing, including paths containing spaces.
{
  printf 'export GODOT_BIN=%q\n' "$GODOT_BIN"
  printf 'export XDG_CONFIG_HOME=%q\n' "$XDG_CONFIG_HOME"
  printf 'export XDG_DATA_HOME=%q\n' "$XDG_DATA_HOME"
  printf 'export XDG_CACHE_HOME=%q\n' "$XDG_CACHE_HOME"
  printf 'export ANDROID_HOME=%q\n' "$ANDROID_HOME"
  printf 'export ANDROID_USER_HOME=%q\n' "$ANDROID_USER_HOME"
  if [[ -n "${JAVA_HOME:-}" ]]; then printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"; fi
} > "$tools_dir/environment.sh"
"$GODOT_BIN" --headless --version
printf '\nReady. Run: source %q\nThen: bash %q\n' "$tools_dir/environment.sh" "$project_dir/tools/run_checks.sh"
