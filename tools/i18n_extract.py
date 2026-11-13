# -*- coding: utf-8 -*-
"""从 .ts 抽出待翻译条目，按 context 分批输出 JSON（供人工/子代理逐条翻译）。

用法:
  python tools/i18n_extract.py            # 生成 i18n/_work/batch_*.json
  python tools/i18n_extract.py --stat     # 只看统计
每个 batch JSON 结构:
  { "batch": "01", "langs": ["zh_HK","zh_TW"],
    "items": [ {"ctx": "StagePage", "src": "上次游玩 · %1", "hk": "", "tw": ""} ] }
只导出「译文为空」或仍标 unfinished 的条目。
"""
import json, os, re, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "i18n")
WORK = os.path.join(I18N, "_work")
BASE = os.path.join(I18N, "shadow_zh_CN.ts")   # 以 zh_CN 为“源清单”基准
BATCH = 80

def load(path):
    return ET.parse(path).getroot()

def items_of(root):
    out = []
    for ctx in root.findall("context"):
        name = ctx.findtext("name") or ""
        for msg in ctx.findall("message"):
            src = msg.findtext("source") or ""
            tr = msg.find("translation")
            txt = (tr.text or "") if tr is not None else ""
            flag = tr.get("type", "") if tr is not None else "unfinished"
            if src.strip() == "":
                continue
            out.append({"ctx": name, "src": src, "tr": txt, "flag": flag})
    return out

def main():
    if not os.path.exists(BASE):
        print("缺少", BASE); return 1
    src_items = items_of(load(BASE))
    # 读已有译文
    hk = load(os.path.join(I18N, "shadow_zh_HK.ts"))
    tw = load(os.path.join(I18N, "shadow_zh_TW.ts"))
    def index(root):
        d = {}
        for ctx in root.findall("context"):
            name = ctx.findtext("name") or ""
            for msg in ctx.findall("message"):
                s = msg.findtext("source") or ""
                tr = msg.find("translation")
                # 没有 type 属性 = 已完成（Qt 的约定）；"unfinished"/"vanished" 才算未完成
                flag = tr.get("type", "") if tr is not None else "unfinished"
                d.setdefault(name, {})[s] = ((tr.text or "") if tr is not None else "", flag)
        return d
    hki, twi = index(hk), index(tw)

    pending = []
    for it in src_items:
        hkv, hkf = hki.get(it["ctx"], {}).get(it["src"], ("", "unfinished"))
        twv, twf = twi.get(it["ctx"], {}).get(it["src"], ("", "unfinished"))
        if (hkv.strip() and hkf != "unfinished") and (twv.strip() and twf != "unfinished"):
            continue
        pending.append({"ctx": it["ctx"], "src": it["src"], "hk": "" if hkf == "unfinished" else hkv, "tw": "" if twf == "unfinished" else twv})

    print("总条目:", len(src_items), "待翻译:", len(pending))
    if "--stat" in sys.argv:
        from collections import Counter
        c = Counter(p["ctx"] for p in pending)
        for k, v in c.most_common():
            print("%5d  %s" % (v, k))
        return 0

    os.makedirs(WORK, exist_ok=True)
    for old in os.listdir(WORK):
        if old.startswith("batch_") and old.endswith(".json"):
            os.remove(os.path.join(WORK, old))
    for i in range(0, len(pending), BATCH):
        chunk = pending[i:i+BATCH]
        no = "%02d" % (i // BATCH + 1)
        path = os.path.join(WORK, "batch_%s.json" % no)
        json.dump({"batch": no, "langs": ["zh_HK", "zh_TW"], "items": chunk}, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("已生成", (len(pending) + BATCH - 1) // BATCH, "个批次 ->", WORK)
    return 0

if __name__ == "__main__":
    sys.exit(main())
