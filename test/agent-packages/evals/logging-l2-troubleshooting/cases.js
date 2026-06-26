// cases.js — enumerate cases/*/ into promptfoo test cases.
// Replaces orchestrator.sh's `for d in cases/*/` discovery.
const fs = require('fs');
const path = require('path');

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
        // Inline contents as vars. promptfoo does NOT substitute per-test vars
        // into the top-level `prompts:` file path, so the prompt is passed as a
        // var (`prompt_text`) and the config prompt is just `{{prompt_text}}`.
        // ground_truth / rubric_yaml feed the judge template.
        prompt_text: fs.readFileSync(
          path.join(casesDir, slug, 'prompt.txt'),
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
      },
    }));
};
