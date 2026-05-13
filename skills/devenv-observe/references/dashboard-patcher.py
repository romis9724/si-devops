"""
Community Grafana 대시보드 JSON 패치.
패치 후에는 reload 대신 Grafana 컨테이너 restart 권장 (phase-playbook 5-1.9 / OBS-E402).
"""
import json
import sys


def fix(o):
    if isinstance(o, dict):
        if "datasource" in o:
            ds = o["datasource"]
            if isinstance(ds, str) and ds.startswith("${DS_"):
                name = ds[5:-1].lower()
                if "loki" in name:
                    o["datasource"] = {"type": "loki", "uid": "loki"}
                else:
                    o["datasource"] = {"type": "prometheus", "uid": "prometheus"}
        for v in o.values():
            fix(v)
    elif isinstance(o, list):
        for v in o:
            fix(v)


def fix_templating_datasource_current(dashboard):
    """Community JSON: templating.list[] type=datasource 의 current 를 프로비저 uid 로 고정."""
    lst = dashboard.get("templating", {}).get("list")
    if not isinstance(lst, list):
        return
    for item in lst:
        if not isinstance(item, dict) or item.get("type") != "datasource":
            continue
        q = (item.get("query") or "").lower()
        uid = "loki" if "loki" in q else "prometheus"
        item["current"] = {
            "selected": True,
            "text": uid,
            "value": uid,
        }


def main():
    if len(sys.argv) != 3:
        print("usage: python dashboard-patcher.py <input.json> <output.json>")
        sys.exit(1)

    inp, outp = sys.argv[1], sys.argv[2]
    d = json.load(open(inp, encoding="utf-8"))
    d.pop("__inputs", None)
    d.pop("__requires", None)
    fix(d)
    fix_templating_datasource_current(d)
    json.dump(d, open(outp, "w", encoding="utf-8"), indent=2)
    print(f"patched: {inp} -> {outp}")


if __name__ == "__main__":
    main()
