#!/usr/bin/env python3
"""增量同步 iCloud 的 TypeX deb 归档到坚果云 WebDAV 镜像。

用法（构建归档 iCloud 后执行，无参数）:
    python3 webdav-sync.py

行为约定（2026-09-29 起，每次构建归档后都要跑一次）:
- 只同步 *.deb（跳过 .DS_Store 等隐藏文件），旧版本两侧都保留
- 远端缺失或文件大小不一致才 PUT；对账 + 幂等，重跑零上传
- 鉴权走 ~/.netrc 的 dav.jianguoyun.com 条目（curl --netrc），本脚本与仓库均不含密码
"""
import os
import re
import subprocess
import sys
import urllib.parse

BASE = "https://dav.jianguoyun.com/dav"
REMOTE_ROOT = BASE + "/TypeX"
ICLOUD = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/TypeX")


def curl(method, url, extra=()):
    return subprocess.run(
        ["curl", "-s", "-m", "300", "--netrc", "-X", method, url,
         "-o", "/dev/null", "-w", "%{http_code}", *extra],
        capture_output=True, text=True).stdout.strip()


def propfind_files(url):
    """Return {filename: size} for files in a collection, or None if absent."""
    code = curl("PROPFIND", url, ("-H", "Depth: 1"))
    if code == "404":
        return None
    if code != "207":
        raise RuntimeError(f"PROPFIND {url} -> HTTP {code}")
    xml = subprocess.run(
        ["curl", "-s", "-m", "300", "--netrc", "-X", "PROPFIND",
         "-H", "Depth: 1", url], capture_output=True, text=True).stdout
    collection = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    files = {}
    for block in re.split(r"<[dD]:response>", xml)[1:]:
        href = re.search(r"<[dD]:href>([^<]*)</[dD]:href>", block)
        size = re.search(r"<[dD]:getcontentlength>(\d+)</[dD]:getcontentlength>", block)
        if not href or not size:
            continue
        name = urllib.parse.unquote(href.group(1).rstrip("/").rsplit("/", 1)[-1])
        if name == collection:
            continue  # 坚果云会把目录自身也返回一条 size=0 记录
        files[name] = int(size.group(1))
    return files


def local_debs(sub):
    return sorted(f for f in os.listdir(os.path.join(ICLOUD, sub))
                  if f.endswith(".deb") and not f.startswith("."))


def main():
    subs = sorted(d for d in os.listdir(ICLOUD)
                  if os.path.isdir(os.path.join(ICLOUD, d)) and not d.startswith("."))
    print(f"本地归档子目录: {subs}")
    root_code = curl("MKCOL", REMOTE_ROOT)
    assert root_code in ("201", "405"), f"MKCOL TypeX -> HTTP {root_code}"
    uploaded = skipped = 0
    for sub in subs:
        code = curl("MKCOL", f"{REMOTE_ROOT}/{sub}")
        assert code in ("201", "405"), f"MKCOL {sub} -> HTTP {code}"
        files = local_debs(sub)
        remote = propfind_files(f"{REMOTE_ROOT}/{sub}") or {}
        print(f"\n[{sub}] 本地 {len(files)} 个 deb，远端已有 {len(remote)} 个")
        for name in files:
            size = os.path.getsize(os.path.join(ICLOUD, sub, name))
            if remote.get(name) == size:
                skipped += 1
                continue
            reason = "远端缺失" if name not in remote else f"大小不一致(远端 {remote.get(name)})"
            code = curl("PUT", f"{REMOTE_ROOT}/{sub}/{urllib.parse.quote(name)}",
                        ("--data-binary", "@" + os.path.join(ICLOUD, sub, name)))
            if code not in ("200", "201", "204"):
                sys.exit(f"上传失败: {sub}/{name} HTTP {code}")
            uploaded += 1
            print(f"  上传: {name} ({size} B, {reason})")
    print(f"\n同步完成：上传 {uploaded}，一致跳过 {skipped}")

    mismatch = []
    for sub in subs:
        remote = propfind_files(f"{REMOTE_ROOT}/{sub}") or {}
        for name in local_debs(sub):
            size = os.path.getsize(os.path.join(ICLOUD, sub, name))
            if remote.get(name) != size:
                mismatch.append(f"  {sub}/{name}: 本地 {size} 远端 {remote.get(name)}")
    print("对账: " + ("全部一致 ✅" if not mismatch else "不一致 ❌\n" + "\n".join(mismatch)))
    sys.exit(1 if mismatch else 0)


if __name__ == "__main__":
    main()
