#!/usr/bin/env python3
"""Generate network/grafana/dashboards/budget.json (Grafana dashboard "Budget").

Dashboards are API-managed (see CLAUDE.md); this generator is the reviewable
source for the first import. After UI edits, the nightly export in
network/grafana/dashboards/ is the truth, not this file.

    python3 nas/budget/dashboard/build_dashboard.py
    network/scripts/manage-grafana.sh import network/grafana/dashboards/budget.json
"""
import json
from pathlib import Path

DS = {"type": "grafana-postgresql-datasource", "uid": "budget-postgres"}
OUT = Path(__file__).resolve().parents[3] / "network/grafana/dashboards/budget.json"

# Expense groups folded to <= 8 stacked series; the small ones go to "Inne".
GROUP_FOLD = "CASE WHEN group_name IN ('Inne', 'Firma (JDG)') THEN 'Inne' ELSE group_name END"
MONTH_START = "date_trunc('month', now())::date"

_id = 0


def panel(kind, title, sql, x, y, w, h, fmt="table", unit="currencyPLN", desc="", **extra):
    global _id
    _id += 1
    p = {
        "id": _id,
        "type": kind,
        "title": title,
        "description": desc,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{
            "refId": "A", "datasource": DS, "editorMode": "code", "format": fmt,
            "rawQuery": True, "rawSql": sql.strip(),
        }],
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "options": {},
    }
    for k, v in extra.items():
        p[k] = v
    return p


def stat(title, sql, x, y, w=4, unit="currencyPLN", desc="", decimals=0, thresholds=None):
    p = panel("stat", title, sql, x, y, w, 4, unit=unit, desc=desc)
    p["fieldConfig"]["defaults"].update({
        "decimals": decimals,
        "color": {"mode": "thresholds"},
        "thresholds": thresholds or {"mode": "absolute", "steps": [{"color": "text", "value": None}]},
    })
    p["options"] = {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "value", "graphMode": "none", "textMode": "value", "justifyMode": "auto"}
    return p


def bars(title, sql, x, y, w, h, stacked, desc=""):
    p = panel("timeseries", title, sql, x, y, w, h, fmt="time_series", desc=desc)
    p["fieldConfig"]["defaults"].update({
        "decimals": 0,
        "custom": {"drawStyle": "bars", "barAlignment": 0, "fillOpacity": 85, "lineWidth": 0,
                   "stacking": {"mode": "normal" if stacked else "none", "group": "A"},
                   "axisSoftMin": 0, "showPoints": "never"},
        "color": {"mode": "palette-classic"},
    })
    p["options"] = {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}}
    p["interval"] = "1M"
    return p


def line(title, sql, x, y, w, h, desc="", legend=False):
    p = panel("timeseries", title, sql, x, y, w, h, fmt="time_series", desc=desc)
    p["fieldConfig"]["defaults"].update({
        "decimals": 0,
        "custom": {"drawStyle": "line", "lineWidth": 2, "fillOpacity": 0, "showPoints": "auto",
                   "pointSize": 8, "spanNulls": True},
        "color": {"mode": "palette-classic"},
    })
    p["options"] = {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": legend},
                    "tooltip": {"mode": "multi", "sort": "none"}}
    return p


def table(title, sql, x, y, w, h, desc="", overrides=None):
    p = panel("table", title, sql, x, y, w, h, desc=desc)
    p["fieldConfig"]["defaults"]["unit"] = "none"
    p["fieldConfig"]["overrides"] = overrides or []
    p["options"] = {"showHeader": True, "cellHeight": "sm", "footer": {"show": False}}
    return p


def pln_cols(*names, red_below_zero=()):
    out = []
    for n in names:
        props = [{"id": "unit", "value": "currencyPLN"}, {"id": "decimals", "value": 2}]
        if n in red_below_zero:
            props += [
                {"id": "custom.cellOptions", "value": {"type": "color-text"}},
                {"id": "thresholds", "value": {"mode": "absolute", "steps": [
                    {"color": "red", "value": None}, {"color": "text", "value": 0}]}},
            ]
        out.append({"matcher": {"id": "byName", "options": n}, "properties": props})
    return out


AVG = f"""
avg_m AS (
  SELECT COALESCE(AVG(inc), 0) AS inc, COALESCE(AVG(exp), 0) AS exp FROM (
    SELECT date_trunc('month', date) m,
           COALESCE(SUM(amount) FILTER (WHERE is_income), 0) inc,
           COALESCE(-SUM(amount) FILTER (WHERE NOT is_income), 0) exp
    FROM v_flows
    WHERE date >= {MONTH_START} - ($avg_months || ' months')::interval AND date < {MONTH_START}
    GROUP BY 1) x)"""
CASH = "cash AS (SELECT COALESCE(SUM(balance), 0) AS v FROM accounts WHERE NOT offbudget AND NOT closed)"

panels = [
    stat("Cash (on-budget accounts)", "SELECT SUM(balance) AS value FROM accounts WHERE NOT offbudget AND NOT closed", 0, 0,
         desc="Current balance of open on-budget accounts."),
    stat("Spent this month", f"SELECT -COALESCE(SUM(amount), 0) AS value FROM v_flows WHERE NOT is_income AND date >= {MONTH_START}", 4, 0,
         desc="Net spending (refunds subtract). Excludes transfers between own accounts."),
    stat("Income this month", f"SELECT COALESCE(SUM(amount), 0) AS value FROM v_flows WHERE is_income AND date >= {MONTH_START}", 8, 0),
    stat("Runway without income", f"WITH {CASH},{AVG} SELECT (cash.v / NULLIF(avg_m.exp + $extra_fixed, 0))::numeric(6,1) AS value FROM cash, avg_m", 12, 0,
         unit="none", decimals=1,
         desc="Months the current cash lasts at the average spending of the last $avg_months full months plus $extra_fixed/month, with no income."),
    stat("To review", "SELECT count(*) AS value FROM v_review_queue", 16, 0, unit="none",
         desc="Uncategorised transactions plus those actual-ai tagged #actual-ai-miss. Categorise them in Actual.",
         thresholds={"mode": "absolute", "steps": [{"color": "text", "value": None}, {"color": "orange", "value": 20}]}),
    stat("Last bank sync", "SELECT EXTRACT(EPOCH FROM now() - max(at)) / 3600 AS value FROM sync_runs WHERE status = 'ok'", 20, 0,
         unit="h", decimals=1, desc="Hours since the last successful sync of any linked account (runs 06:20, 14:20, 21:20).",
         thresholds={"mode": "absolute", "steps": [{"color": "text", "value": None}, {"color": "orange", "value": 26}]}),

    bars("Monthly spending by category group", f"""
SELECT date_trunc('month', date) AS time, {GROUP_FOLD} AS metric, -SUM(amount) AS value
FROM v_flows
WHERE NOT is_income AND category_id IS NOT NULL AND $__timeFilter(date)
GROUP BY 1, 2 ORDER BY 1, 2""", 0, 4, 14, 10, stacked=True,
         desc="Categorised spending only; uncategorised rows are in the review queue. Small groups fold into Inne."),
    bars("Income vs spending", """
SELECT date_trunc('month', date) AS time,
       COALESCE(SUM(amount) FILTER (WHERE is_income), 0) AS "Income",
       COALESCE(-SUM(amount) FILTER (WHERE NOT is_income), 0) AS "Spending"
FROM v_flows WHERE $__timeFilter(date) GROUP BY 1 ORDER BY 1""", 14, 4, 10, 10, stacked=False),

    table("Budget this month", f"""
SELECT c.group_name AS "Group", c.name AS "Category", bm.budgeted AS "Budgeted",
       -bm.spent AS "Spent", bm.balance AS "Left"
FROM budget_months bm JOIN categories c ON c.id = bm.category_id
WHERE bm.month = {MONTH_START} AND NOT c.is_income AND NOT c.hidden
ORDER BY c.group_name, c.name""", 0, 14, 12, 12,
          desc="Envelope state from Actual. Left < 0 = overspent.",
          overrides=pln_cols("Budgeted", "Spent", "Left", red_below_zero=("Left",))),
    line("Net worth (all accounts)", """
SELECT m AS time, (SELECT COALESCE(SUM(amount), 0) FROM transactions t
                   WHERE NOT t.is_parent AND t.date < m + interval '1 month') AS "Net worth"
FROM generate_series(date_trunc('month', $__timeFrom()::timestamptz), date_trunc('month', now()), '1 month') m
ORDER BY 1""", 12, 14, 12, 12, desc="End-of-month sum of every account, including off-budget ones."),

    line("Cash projection (what-if)", f"""
WITH {CASH},{AVG},
sim AS (
  SELECT g AS n,
         CASE WHEN g <= $months_no_income THEN 0 ELSE avg_m.inc * (1 - $income_cut_pct / 100.0) END
         - (avg_m.exp + $extra_fixed) AS net
  FROM avg_m, generate_series(1, 24) g)
SELECT date_trunc('month', now()) + (n || ' months')::interval AS time,
       (SELECT v FROM cash) + SUM(net) OVER (ORDER BY n) AS "Projected cash"
FROM sim ORDER BY n""", 0, 26, 16, 10,
         desc="24 months from today's cash. Averages of the last $avg_months full months; "
              "no income for $months_no_income months, then income cut by $income_cut_pct %; "
              "plus $extra_fixed PLN/month extra fixed cost (e.g. ZUS). Set these in the variables bar."),
    table("Top payees this month", f"""
SELECT COALESCE(payee_name, imported_payee, '?') AS "Payee", count(*) AS "Count", -SUM(amount) AS "Spent"
FROM v_flows WHERE NOT is_income AND date >= {MONTH_START}
GROUP BY 1 ORDER BY 3 DESC LIMIT 15""", 16, 26, 8, 10, overrides=pln_cols("Spent")),

    table("Review queue", """
SELECT date AS "Date", account_name AS "Account", COALESCE(payee_name, imported_payee) AS "Payee",
       amount AS "Amount", notes AS "Notes"
FROM v_review_queue ORDER BY date DESC LIMIT 100""", 0, 36, 14, 10,
          desc="Fix these in Actual; actual-ai learns nothing by itself, so for recurring payees add a rule.",
          overrides=pln_cols("Amount")),
    table("Bank sync per account", """
SELECT a.name AS "Account", last.at AS "Last run", last.status AS "Status",
       last.new_count AS "New", ok.ok_at AS "Last OK", last.error AS "Error"
FROM accounts a
LEFT JOIN LATERAL (SELECT * FROM sync_runs s WHERE s.account_id = a.id ORDER BY at DESC LIMIT 1) last ON true
LEFT JOIN LATERAL (SELECT max(at) AS ok_at FROM sync_runs s WHERE s.account_id = a.id AND status = 'ok') ok ON true
WHERE a.sync_source IS NOT NULL AND NOT a.closed ORDER BY 1""", 14, 36, 10, 5,
          desc="Enable Banking-linked accounts. Error mentioning consent/auth → reauthorize in Actual."),
    table("Worker jobs (last 24 h)", """
SELECT job AS "Job", started_at AS "Started", status AS "Status", detail AS "Detail"
FROM job_runs WHERE started_at > now() - interval '24 hours' AND (job <> 'export' OR status <> 'ok')
ORDER BY started_at DESC LIMIT 30""", 14, 41, 10, 5, desc="Successful exports are hidden (they run every 30 min)."),
]


def custom_var(name, label, options, default):
    return {
        "type": "custom", "name": name, "label": label, "query": ",".join(options),
        "current": {"text": default, "value": default},
        "options": [{"text": o, "value": o, "selected": o == default} for o in options],
        "hide": 0, "multi": False, "includeAll": False,
    }


dashboard = {
    "uid": "budget",
    "title": "Budget",
    "tags": ["budget", "finance"],
    "timezone": "Europe/Warsaw",
    "time": {"from": "now-12M/M", "to": "now"},
    "refresh": "30m",
    "schemaVersion": 41,
    "editable": True,
    "graphTooltip": 1,
    "description": "Household budget (Actual Budget mirror). Source: nas/budget/notes.md",
    "templating": {"list": [
        custom_var("avg_months", "Average over (months)", ["3", "6", "12"], "6"),
        custom_var("months_no_income", "Months without income", [str(i) for i in range(0, 7)] + ["12", "24"], "0"),
        custom_var("income_cut_pct", "Income cut %", ["0", "10", "20", "30", "50", "75", "100"], "0"),
        {"type": "textbox", "name": "extra_fixed", "label": "Extra fixed cost PLN/month (e.g. ZUS)",
         "query": "0", "current": {"text": "0", "value": "0"}, "hide": 0},
    ]},
    "panels": panels,
}

OUT.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n")
print(f"wrote {OUT} ({len(panels)} panels)")
