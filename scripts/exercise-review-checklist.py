#!/usr/bin/env python3
"""Turn the review results into a checklist: checklist.html (tick boxes, saved in the
browser, with a button to copy your verdicts) and checklist.csv."""
import csv, html, json, os, sys

results = json.load(open(sys.argv[1]))
out = sys.argv[2]


def stamp(seconds):
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


with open(os.path.join(out, 'checklist.csv'), 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['#', 'Exercise', 'Where', 'Movement from', 'At (video)', 'Automatic check', 'What the check found', 'Your verdict (keep / drop)', 'Notes'])
    for r in results:
        w.writerow([r['number'], r['title'], r['group'], r['source'], stamp(r['startSecond']), r['verdict'], '; '.join(r['flags']), '', ''])

rows = []
for r in results:
    ok = r['verdict'] == 'PASS'
    rows.append(f"""<tr class="{'pass' if ok else 'check'}" data-n="{r['number']}" data-title="{html.escape(r['title'])}">
<td class="n">{r['number']}</td><td><b>{html.escape(r['title'])}</b><br><small>{html.escape(r['group'])} · {html.escape(r['source'])}</small></td>
<td>{stamp(r['startSecond'])}</td>
<td class="auto">{'Pass' if ok else 'Check'}<br><small>{html.escape('; '.join(r['flags']))}</small></td>
<td class="v"><label><input type="radio" name="v{r['number']}" value="keep"> Keep</label>
<label><input type="radio" name="v{r['number']}" value="drop"> Drop</label></td>
<td><input type="text" class="note" placeholder="note"></td></tr>""")

passed = sum(1 for r in results if r['verdict'] == 'PASS')
page = f"""<!doctype html><meta charset="utf-8"><title>Nourlo exercise review</title>
<style>
body{{font:15px -apple-system,system-ui,sans-serif;margin:32px auto;max-width:980px;color:#1e2a40;padding:0 16px}}
h1{{margin:0 0 4px}} p{{color:#6b7385}}
table{{border-collapse:collapse;width:100%}} td,th{{padding:9px 10px;border-bottom:1px solid #e6e2e0;vertical-align:top;text-align:left}}
th{{position:sticky;top:0;background:#fff;font-size:13px;color:#6b7385}}
.n{{font-weight:700;color:#6b7385}} small{{color:#6b7385}}
tr.pass .auto{{color:#2e8b57;font-weight:600}} tr.check .auto{{color:#c4701a;font-weight:600}}
.v label{{display:block;white-space:nowrap}} .note{{width:150px;padding:5px;border:1px solid #d8d2d0;border-radius:6px}}
button{{font:inherit;padding:9px 16px;border-radius:10px;border:0;background:#1e2a40;color:#fff;margin:14px 8px 14px 0;cursor:pointer}}
#copied{{color:#2e8b57}}
</style>
<h1>Nourlo exercise review</h1>
<p>{len(results)} movements · automatic checks: {passed} pass, {len(results) - passed} to check · watch <b>review.mp4</b>, each one is numbered and the time is listed here.</p>
<p>The automatic check looks for: body through the floor, hips collapsing to the floor, feet floating, knees folding too far, arms or legs passing through the body, freezing, popping, and a jump where the loop restarts. It cannot judge whether the form is good coaching. That is your call.</p>
<button onclick="copy()">Copy my verdicts</button><button onclick="mark('pass','keep')">Mark all auto-pass as Keep</button><span id="copied"></span>
<table><tr><th>#</th><th>Exercise</th><th>At</th><th>Automatic check</th><th>Your verdict</th><th>Notes</th></tr>
{''.join(rows)}</table>
<script>
const key='nourlo-review';
const saved=JSON.parse(localStorage.getItem(key)||'{{}}');
document.querySelectorAll('tr[data-n]').forEach(tr=>{{
  const n=tr.dataset.n, s=saved[n]||{{}};
  tr.querySelectorAll('input[type=radio]').forEach(i=>{{ if(i.value===s.v) i.checked=true; i.onchange=save; }});
  const note=tr.querySelector('.note'); note.value=s.note||''; note.oninput=save;
}});
function save(){{
  const d={{}};
  document.querySelectorAll('tr[data-n]').forEach(tr=>{{
    const c=tr.querySelector('input[type=radio]:checked');
    d[tr.dataset.n]={{v:c?c.value:'',note:tr.querySelector('.note').value}};
  }});
  localStorage.setItem(key,JSON.stringify(d));
}}
function mark(cls,v){{ document.querySelectorAll('tr.'+cls+' input[value='+v+']').forEach(i=>i.checked=true); save(); }}
function copy(){{
  const keep=[],drop=[],notes=[];
  document.querySelectorAll('tr[data-n]').forEach(tr=>{{
    const c=tr.querySelector('input[type=radio]:checked'), n=tr.dataset.n, note=tr.querySelector('.note').value;
    if(c&&c.value==='keep') keep.push(n); if(c&&c.value==='drop') drop.push(n);
    if(note) notes.push('#'+n+' '+tr.dataset.title+': '+note);
  }});
  const text='KEEP: '+keep.join(', ')+'\\nDROP: '+drop.join(', ')+(notes.length?'\\nNOTES:\\n'+notes.join('\\n'):'');
  navigator.clipboard.writeText(text); document.getElementById('copied').textContent='Copied. Paste it to Claude.';
}}
</script>"""
open(os.path.join(out, 'checklist.html'), 'w').write(page)
print('checklist:', len(results), 'movements,', passed, 'pass')
