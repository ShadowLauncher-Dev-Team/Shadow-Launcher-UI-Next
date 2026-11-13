# -*- coding: utf-8 -*-
"""从 shadow_zh_CN.ts 抽出待翻译条目，按批次输出 JSON（供人工逐条翻译）。

用法:
  python tools/i18n_extract.py                       # 默认 langs=zh_HK,zh_TW
  python tools/i18n_extract.py --langs en            # 只处理 en
  python tools/i18n_extract.py --stat                # 只看统计
每个 batch JSON: { "batch":"01", "langs":["en"], "items":[{"ctx":..,"src":..,"en":""}] }
只导出「译文为空」或仍标 unfinished/vanished 的条目。
"""
import json, os, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, "i18n")
WORK = os.path.join(I18N, "_work")
BASE = os.path.join(I18N, "shadow_zh_CN.ts")
BATCH = 80
ALL_LANGS = ["zh_HK", "zh_TW", "en"]


def items_of(path):
    root = ET.parse(path).getroot()
    out = []
    for ctx in root.findall("context"):
        name = ctx.findtext("name") or ""
        for msg in ctx.findall("message"):
            src = msg.findtext("source") or ""
            if src.strip():
                out.append({"ctx": name, "src": src})
    return out


def index(path):
    """(context, source) -> (译文, 是否已完成)"""
    if not os.path.exists(path):
        return {}
    root = ET.parse(path).getroot()
    d = {}
    for ctx in root.findall("context"):
        name = ctx.findtext("name") or ""
        for msg in ctx.findall("message"):
            src = msg.findtext("source") or ""
            tr = msg.find("translation")
            txt = (tr.text or "") if tr is not None else ""
            kind = tr.get("type", "") if tr is not None else "unfinished"
            # Qt 约定：没有 type 属性 = 已完成
            done = bool(txt.strip()) and kind not in ("unfinished", "vanished")
            d.setdefault(name, {})[src] = (txt, done)
    return d


def main():
    langs = ALL_LANGS
    for a in sys.argv:
        if a.startswith("--langs"):
            langs = [x.strip() for x in a.split("=", 1)[1].split(",")] if "=" in a else ALL_LANGS
    if "--langs" in sys.argv:
        i = sys.argv.index("--langs")
        if i + 1 < len(sys.argv):
            langs = [x.strip() for x in sys.argv[i + 1].split(",")]

    src_items = items_of(BASE)
    idx = {L: index(os.path.join(I18N, "shadow_%s.ts" % L)) for L in langs}

    pending = []
    for it in src_items:
        vals, needed = {}, False
        for L in langs:
            v, done = idx[L].get(it["ctx"], {}).get(it["src"], ("", False))
            vals[L] = "" if not done else v
            if not done:
                needed = True
        if needed:
            row = {"ctx": it["ctx"], "src": it["src"]}
            row.update(vals)
            pending.append(row)

    print("总条目:", len(src_items), "待翻译:", len(pending), "语言:", ",".join(langs))
    if "--stat" in sys.argv:
        from collections import Counter
        c = Counter(p["ctx"] for p in pending)
        for k, v in c.most_common():
            print("%5d  %s" % (v, k))
        return 0

    os.makedirs(WORK, exist_ok=True)
    for old in os.listdir(WORK):
        if old.startswith("batch_") and old.endswith(".json") and "_" in old:
            os.remove(os.path.join(WORK, old))
    n = (len(pending) + BATCH - 1) // BATCH
    for i in range(0, len(pending), BATCH):
        no = "%02d" % (i // BATCH + 1)
        json.dump({"batch": no, "langs": langs, "items": pending[i:i + BATCH]},
                  open(os.path.join(WORK, "batch_%s.json" % no), "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
    print("已生成", n, "个批次 ->", WORK)
    return 0


if __name__ == "__main__":
    sys.exit(main())
