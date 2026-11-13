# -*- coding: utf-8 -*-
"""把翻译批次 JSON（已填 hk/tw）合并回 .ts。

用法:
  python tools/i18n_apply.py i18n/_work/batch_01.json
  python tools/i18n_apply.py --all        # 合并 _work 下所有已填批次
规则:
  - 只写 hk / tw 非空的条目；空的不动
  - 与 source 完全相同的译文视为“不需要翻译”，标 vanished? 不：标 finished 但保留原文
  - 写完把该条 translation 的 type 清掉（视为已完成）
"""
import glob, json, os, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "i18n")

def merge(ts_path, mapping):
    tree = ET.parse(ts_path)
    root = tree.getroot()
    n = 0
    for ctx in root.findall("context"):
        name = ctx.findtext("name") or ""
        for msg in ctx.findall("message"):
            src = msg.findtext("source") or ""
            key = (name, src)
            if key not in mapping:
                continue
            val = mapping[key]
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
    if "--all" in sys.argv:
        files = sorted(glob.glob(os.path.join(I18N, "_work", "batch_*.json")))
    else:
        files = sys.argv[1:]
    hk_map, tw_map = {}, {}
    for f in files:
        data = json.load(open(f, encoding="utf-8"))
        for it in data["items"]:
            if it.get("hk", "").strip():
                hk_map[(it["ctx"], it["src"])] = it["hk"]
            if it.get("tw", "").strip():
                tw_map[(it["ctx"], it["src"])] = it["tw"]
    a = merge(os.path.join(I18N, "shadow_zh_HK.ts"), hk_map)
    b = merge(os.path.join(I18N, "shadow_zh_TW.ts"), tw_map)
    print("写入 zh_HK:", a, " zh_TW:", b, " 来自", len(files), "个批次")
    return 0

if __name__ == "__main__":
    sys.exit(main())
