#!/usr/bin/env node
// report.js — turn the last promptfoo run into results/<run>/summary.md.
//
// Reads the combined JSON that `npx promptfoo eval --output` writes
// (results/<run>/all.json, located via results/LAST_RUN or a path argument),
// and summarizes it from promptfoo's NATIVE fields: the named assertion scores
// (metric: rubric, metric: routing), per-result cost, and numTurns.
//
// L1 difference from L2: routing has TWO skill-used components (classification
// + outcome). A case's routing passes only when BOTH pass. A `disposition`
// column (from meta.yaml via cases.js vars) makes per-branch performance visible.
//
// Usage: node report.js [path/to/all.json]

const fs = require('fs');
const path = require('path');

const EVAL_DIR = __dirname;

function resolveRunFile(arg) {
  if (arg) return arg;
  const last = path.join(EVAL_DIR, 'results/LAST_RUN');
  if (!fs.existsSync(last)) {
    console.error('no results/LAST_RUN; run `make eval` first');
    process.exit(1);
  }
  const runId = fs.readFileSync(last, 'utf8').trim();
  return path.join(EVAL_DIR, 'results', runId, 'all.json');
}

function mean(xs) {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
}
function fmt(x, digits = 2) {
  return x === null ? 'n/a' : x.toFixed(digits);
}

// rubric: the single named rubric component's score.
function rubricScore(result) {
  const comps = (result.gradingResult || {}).componentResults || [];
  for (const c of comps) {
    const a = c.assertion || {};
    if ((a.metric || a.type) === 'rubric') return c.score;
  }
  return null;
}

// routing: every component whose metric is `routing` must pass (both skills ran).
// Returns 1 / 0, or null when no routing component is present.
function routingPass(result) {
  const comps = (result.gradingResult || {}).componentResults || [];
  const routes = comps.filter(
    (c) => ((c.assertion || {}).metric || (c.assertion || {}).type) === 'routing',
  );
  if (!routes.length) return null;
  return routes.every((c) => c.pass) ? 1 : 0;
}

function main() {
  const runFile = resolveRunFile(process.argv[2]);
  if (!fs.existsSync(runFile)) {
    console.error(`run file not found: ${runFile}`);
    process.exit(1);
  }
  const data = JSON.parse(fs.readFileSync(runFile, 'utf8'));
  const res = data.results || {};
  const rows = res.results || [];
  const runId = path.basename(path.dirname(runFile));

  // Group repeats by case description.
  const byCase = new Map();
  for (const r of rows) {
    const name = r.description || (r.vars || {}).case || '(unnamed)';
    if (!byCase.has(name)) byCase.set(name, []);
    byCase.get(name).push(r);
  }

  const lines = [];
  lines.push(`# Eval run ${runId}`, '');
  lines.push(
    'Native promptfoo metrics (with-pkg branch). `rubric` is the judge score ' +
      '(0–1); `routing` passes only when BOTH skills ran ' +
      '(`logging-l1-classification` then `logging-l1-outcome`). Cost is ' +
      "promptfoo's own per-call computation from model token rates.",
    '',
  );
  lines.push(
    '| Case | disposition | repeats | rubric (mean) | routing (pass-rate) | overall pass | cost (mean) | turns (mean) |',
  );
  lines.push('|---|---|---|---|---|---|---|---|');

  let allRubric = [];
  let allRouting = [];
  let allPass = 0;
  let allRuns = 0;
  let totalCost = 0;
  let allScores = [];

  for (const [name, reps] of [...byCase.entries()].sort()) {
    const rubric = [];
    const routing = [];
    const costs = [];
    const turns = [];
    let passes = 0;
    const disposition = (reps[0].vars || {}).disposition || '';
    for (const r of reps) {
      const rs = rubricScore(r);
      if (rs !== null) rubric.push(rs);
      const rp = routingPass(r);
      if (rp !== null) routing.push(rp);
      const gr = r.gradingResult || {};
      if (gr.pass) passes += 1;
      if (typeof gr.score === 'number') allScores.push(gr.score);
      const cost = (r.response || {}).cost;
      if (typeof cost === 'number') {
        costs.push(cost);
        totalCost += cost;
      }
      const nt = ((r.response || {}).metadata || {}).numTurns;
      if (typeof nt === 'number') turns.push(nt);
    }
    allRubric = allRubric.concat(rubric);
    allRouting = allRouting.concat(routing);
    allPass += passes;
    allRuns += reps.length;

    const routingRate = routing.length ? mean(routing) : null;
    lines.push(
      `| ${name} | ${disposition || 'n/a'} | ${reps.length} | ${fmt(mean(rubric))} | ` +
        `${routingRate === null ? 'n/a' : `${(routingRate * 100).toFixed(0)}%`} | ` +
        `${passes}/${reps.length} | $${fmt(mean(costs), 4)} | ${fmt(mean(turns), 1)} |`,
    );
  }

  const meanScore = mean(allScores);
  const costPerScore =
    meanScore && allRuns ? totalCost / Math.max(meanScore * allRuns, 0.001) : null;

  lines.push('', '## Totals', '');
  lines.push(`- Cases: ${byCase.size}; runs: ${allRuns}; overall pass: ${allPass}/${allRuns}.`);
  lines.push(`- Mean rubric score: ${fmt(mean(allRubric))}.`);
  lines.push(
    `- Routing pass-rate: ${allRouting.length ? `${(mean(allRouting) * 100).toFixed(0)}%` : 'n/a'}.`,
  );
  lines.push(`- Mean overall score: ${fmt(meanScore, 3)}.`);
  lines.push(`- Total cost: $${totalCost.toFixed(4)} across ${allRuns} runs.`);
  lines.push(
    `- Cost per score-unit (lower is better): ${
      costPerScore === null ? 'n/a' : `$${costPerScore.toFixed(4)}`
    }. A score-unit is one fully passed run; partial scores count fractionally.`,
  );
  lines.push('');

  const out = path.join(path.dirname(runFile), 'summary.md');
  fs.writeFileSync(out, lines.join('\n'));
  console.log(`wrote ${out}`);
  console.log(lines.join('\n'));
}

main();
