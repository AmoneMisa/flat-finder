import { readFileSync, writeFileSync } from 'node:fs';

const path = 'backend/src/countries.js';
let source = readFileSync(path, 'utf8');

source = `import {canonicalCity} from '@whiteslove/parsing-lexicon/geography';\nimport {countryByCode} from '@whiteslove/parsing-lexicon/countries';\n\n${source}`;
source = source.replace('export const COUNTRIES = {', 'const SOURCE_COUNTRIES = {');

const lines = source.split('\n');
const out = [];
let skipObject = false;
let depth = 0;

for (const line of lines) {
  if (!skipObject && /^    (?:name|currency):\s*['"]/u.test(line)) continue;

  if (!skipObject && /^    cityAliases:\s*\{/u.test(line)) {
    skipObject = true;
    depth = (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
    if (depth <= 0) skipObject = false;
    continue;
  }

  if (skipObject) {
    depth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
    if (depth <= 0) skipObject = false;
    continue;
  }

  out.push(line);
}
source = out.join('\n');

const tailStart = source.indexOf('\nfunction normalizeCityName(value) {');
if (tailStart < 0) throw new Error('normalizeCityName tail not found');

source = source.slice(0, tailStart) + `\n\nexport const COUNTRIES = Object.freeze(Object.fromEntries(\n  Object.entries(SOURCE_COUNTRIES).map(([code, config]) => {\n    const shared = countryByCode(code);\n    return [\n      code,\n      Object.freeze({\n        ...config,\n        name: shared?.canonical ?? code,\n        currency: shared?.currency ?? null,\n      }),\n    ];\n  }),\n));\n\nexport function canonicalCityName(countryCode, value) {\n  const raw = String(value ?? '').trim();\n  if (!raw) return '';\n  return canonicalCity(raw, countryCode) || raw;\n}\n\nexport const COUNTRY_CODES = Object.keys(COUNTRIES);\n`;

writeFileSync(path, source);
