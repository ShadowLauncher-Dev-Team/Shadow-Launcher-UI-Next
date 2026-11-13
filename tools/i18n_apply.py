# -*- coding: utf-8 -*-
"""把已填好的翻译批次 JSON 合并回对应语言的 .ts。

用法:
  python tools/i18n_apply.py i18n/_work/batch_01.json
  python tools/i18n_apply.py --all
规则: 只写非空译文；写完清掉 translation 的 type 属性（= 已完成）。
条目里出现哪些语言 key，就写哪些语言。
"""
import glob, json, os, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "i18n")
LANGS = ["zh_HK", "zh_TW", "en"]


def merge(ts_path, mapping):
    if not os.path.exists(ts_path) or not mapping:
        return 0
    tree = ET.parse(ts_path)
    root = tree.getroot()
    n = 0
    for ctx in root.findall("context"):
        name = ctx.findtext("name") or ""
        for msg in ctx.findall("message"):
            src = msg.findtext("source") or ""
            val = mapping.get((name, src), "")
            if not val.strip():
                continue
            tr = msg.find("translation")
            if tr is None:
                tr = ET.SubElement(msg, "translation")
            tr.text = val
            if "type" in tr.attrib:
                del tr.attrib["type"]
            n += 1
    tree.write(ts_path, encoding="utf-8", xml_declaration=True)
    return n


def main():
    files = sorted(glob.glob(os.path.join(I18N, "_work", "batch_*.json"))) \
        if "--all" in sys.argv else sys.argv[1:]
    maps = {L: {} for L in LANGS}
    for f in files:
        data = json.load(open(f, encoding="utf-8"))
        for it in data["items"]:
            for L in LANGS:
                v = it.get(L, "")
                if isinstance(v, str) and v.strip():
                    maps[L][(it["ctx"], it["src"])] = v
    for L in LANGS:
        n = merge(os.path.join(I18N, "shadow_%s.ts" % L), maps[L])
        if n:
            print("写入 %s: %d" % (L, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
