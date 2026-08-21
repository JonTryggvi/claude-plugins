#!/usr/bin/env python3
"""Fold a reconcile run's proposals into a /time-records fixture as posted records.

Used by the idempotency test: it simulates "the user approved these and they were
written", so the next run reads them back as logged. That is the mechanism that
actually prevents duplicates — ActiveCollab holding the hours — rather than any
local memory, so the test exercises the real protection.
"""
import json, io, sys, datetime

run, trf = sys.argv[1], sys.argv[2]
r = json.load(io.open(run, encoding='utf-8'))
doc = json.load(io.open(trf, encoding='utf-8'))
nid = 70000
added = 0
for p in r.get('proposals', []):
    nid += 1
    added += 1
    d = datetime.datetime.strptime(p['record_date'], '%Y-%m-%d').replace(tzinfo=datetime.timezone.utc)
    doc['time_records'].append({
        "id": nid, "project_id": p['project_id'], "record_date": int(d.timestamp()),
        "value": p['value'], "user_id": 6, "user_name": "Jón Tryggvi Unnarsson",
        "job_type_id": p.get('job_type_id') or 1, "billable_status": 1,
        "invoice_item_id": 0, "is_trashed": False,
        "summary": "posted by the first run", "parent_type": "Project",
        "parent_id": p['project_id']})
io.open(trf, 'w', encoding='utf-8').write(json.dumps(doc, ensure_ascii=False, indent=1))
print("folded %d posted record(s) into the fixture" % added)
