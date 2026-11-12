// Prompt A/B harness for actual-ai (2026-11-12 audit). Inputs live OUTSIDE the repo
// (they are real transactions): sample.json [{ip, notes, amount, date, label}] and
// cats.txt (id|name|group_id|group_name from the Postgres mirror). Needs `npm i handlebars`.
// node run.mjs <template.hbs> <model> <ollama base> [limit]  -> prints accuracy, writes results-<tpl>-<model>.json
import fs from 'node:fs';
import Handlebars from 'handlebars';

const [tplFile, model, base, limit] = process.argv.slice(2);
Handlebars.registerHelper('incIndex', (i) => i + 1);
const tpl = Handlebars.compile(fs.readFileSync(tplFile, 'utf8'));
const cats = fs.readFileSync('cats.txt', 'utf8').trim().split('\n').map((l) => {
  const [id, name, group_id, group_name] = l.split('|');
  return { id, name, group_id, group_name };
});
const groups = [];
for (const c of cats) {
  let g = groups.find((x) => x.id === c.group_id);
  if (!g) groups.push((g = { id: c.group_id, name: c.group_name, categories: [] }));
  g.categories.push({ id: c.id, name: c.name });
}
const byId = Object.fromEntries(cats.map((c) => [c.id, c.name]));
const sample = JSON.parse(fs.readFileSync('sample.json', 'utf8')).slice(0, Number(limit) || undefined);

const results = [];
let ok = 0;
for (const r of sample) {
  const prompt = tpl({
    categoryGroups: groups,
    amount: Math.abs(r.amount),
    type: r.amount < 0 ? 'Outcome' : 'Income',
    description: r.notes,
    importedPayee: r.ip,
    payee: r.ip,
    date: r.date,
    rules: [],
  });
  let answer = '?';
  try {
    const res = await fetch(`${base}/api/chat`, {
      method: 'POST',
      body: JSON.stringify({ model, stream: false, think: model.includes('gpt-oss') ? 'low' : false, ...(model.includes('gpt-oss') ? {} : { format: 'json' }), options: { temperature: 0 }, messages: [{ role: 'user', content: prompt }] }),
      signal: AbortSignal.timeout(180_000),
    });
    const j = await res.json();
    const txt = j.message.content; const parsed = JSON.parse(txt.slice(txt.indexOf('{'), txt.lastIndexOf('}') + 1));
    answer = byId[parsed.categoryId] ?? parsed.categoryId ?? JSON.stringify(parsed);
  } catch (e) {
    answer = `ERR ${e.message}`;
  }
  if (answer === r.label) ok++;
  results.push({ ip: r.ip, notes: r.notes, amount: r.amount, label: r.label, answer });
}
const name = `results-${tplFile.replace('.hbs', '')}-${model.replace(/[:/]/g, '_')}.json`;
fs.writeFileSync(name, JSON.stringify(results, null, 1));
console.log(`${tplFile} ${model}: ${ok}/${sample.length} = ${((100 * ok) / sample.length).toFixed(1)}%`);
