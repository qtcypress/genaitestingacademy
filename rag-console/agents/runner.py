"""Run the Concierge suites and report per-case results.

    python -m agents.runner              all three suites
    python -m agents.runner red          one suite
    python -m agents.runner red RT-MCP-02   one case, verbose
"""
import json
import os
import sys

from . import checks
from .orchestrator import run_request

HERE = os.path.dirname(os.path.abspath(__file__))
SUITES = {"blue": "blue_team.json", "red": "red_team.json", "obs": "observability.json"}


def load(suite):
    with open(os.path.join(HERE, "tests", SUITES[suite]), encoding="utf-8") as f:
        return json.load(f)


def run_case(case, mode="scripted"):
    trace = run_request(case["request"], mode=mode, area=case.get("area"))
    results = []
    for a in case["assert"]:
        status, detail = checks.run_assertion(a, trace)
        results.append({"assert": a, "status": status, "detail": detail})
    if any(r["status"] == "fail" for r in results):
        verdict = "fail"
    elif any(r["status"] == "unknown" for r in results):
        verdict = "weak"
    else:
        verdict = "pass"
    return {"id": case["id"], "category": case["category"], "verdict": verdict,
            "results": results, "trace": trace}


def run_suite(suite, mode="scripted"):
    return [run_case(c, mode) for c in load(suite)]


def main():
    args = sys.argv[1:]
    which = [args[0]] if args and args[0] in SUITES else list(SUITES)
    only = args[1] if len(args) > 1 else None

    grand = {"pass": 0, "weak": 0, "fail": 0}
    unimplemented = set()

    for suite in which:
        cases = [c for c in load(suite) if not only or c["id"] == only]
        if not cases:
            continue
        print("\n=== %s (%d cases) ===" % (suite.upper(), len(cases)))
        for case in cases:
            r = run_case(case)
            grand[r["verdict"]] += 1
            mark = {"pass": "PASS", "weak": "WEAK", "fail": "FAIL"}[r["verdict"]]
            print("  %-4s %-11s %s" % (mark, r["id"], case["category"]))
            for a in r["results"]:
                if a["status"] != "pass" or only:
                    print("        %-6s %-38s %s" % (a["status"], a["assert"], a["detail"]))
                if a["status"] == "unknown" and "no check implemented" in a["detail"]:
                    unimplemented.add(a["assert"])
            if only:
                print("\n--- trace ---")
                t = r["trace"]
                print("plan:", json.dumps(t.get("plan"), indent=1)[:900])
                print("steps:", t.get("step_count"), "| total:", t.get("total"),
                      "| outcome:", json.dumps(t.get("outcome"), default=str)[:300])
                for c in t.get("tool_calls", []):
                    print("  %2d %-20s %-12s %s" % (c["seq"], c["tool"], c["caller"],
                                                    "ok" if c.get("ok") else "ERR " + str(c.get("error"))[:60]))

    print("\n===== total: %d pass, %d weak, %d fail =====" %
          (grand["pass"], grand["weak"], grand["fail"]))
    if unimplemented:
        print("\nassertions with no implementation (%d):" % len(unimplemented))
        for a in sorted(unimplemented):
            print("  -", a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
