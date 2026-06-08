// cases.js — enumerate cases/*/ into promptfoo test cases.
const fs = require('fs');
const path = require('path');

// Pull `disposition:` out of meta.yaml without a YAML dep — it is a single
// top-level scalar. report.js reads it back from vars to add a branch column.
function dispositionOf(metaPath) {
  try {
    const m = fs.readFileSync(metaPath, 'utf8').match(/^disposition:\s*(\S+)/m);
    return m ? m[1] : '';
  } catch {
    return '';
  }
}

module.exports = async function () {
  const casesDir = path.join(__dirname, 'cases');
  return fs
    .readdirSync(casesDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort()
    .map((slug) => ({
      description: slug,
      vars: {
        case: slug,
        // Inline contents as vars. The ticket text feeds the shared prompt as
        // `prompt_text`; ground_truth / rubric_yaml feed the judge template.
        prompt_text: fs.readFileSync(
          path.join(casesDir, slug, 'ticket.txt'),
          'utf8',
        ),
        ground_truth: fs.readFileSync(
          path.join(casesDir, slug, 'ground_truth.md'),
          'utf8',
        ),
        rubric_yaml: fs.readFileSync(
          path.join(casesDir, slug, 'rubric.yaml'),
          'utf8',
        ),
        disposition: dispositionOf(path.join(casesDir, slug, 'meta.yaml')),
      },
    }));
};
