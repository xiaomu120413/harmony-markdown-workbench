import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = path.join(root, 'entry/.test/default');
const [logArg, stampArg] = process.argv.slice(2);
if (!logArg || !stampArg) {
  throw new Error('Usage: node scripts/check/check-sdk-results.mjs <build-log> <start-stamp>');
}
const started = Number(fs.readFileSync(path.resolve(root, stampArg), 'utf8').trim());
if (!Number.isFinite(started) || started <= 0 || started > Date.now()) {
  throw new Error('Invalid SDK test start timestamp');
}
const log = fs.readFileSync(path.resolve(root, logArg), 'utf8').replace(/\x1b\[[0-9;]*m/g, '');
if (!log.includes('BUILD SUCCESSFUL') || /BUILD FAILED|Error in |COMPILE RESULT:FAIL/.test(log)) {
  throw new Error('SDK build did not complete successfully');
}
function fresh(relative) {
  const file = path.join(base, relative);
  if (fs.statSync(file).mtimeMs < started) { throw new Error(`Stale SDK result: ${relative}`); }
  return fs.readFileSync(file, 'utf8');
}
const results = fresh('intermediates/test/coverage_data/test_result.txt');
const engineLog = fresh('intermediates/test/coverage_data/coverage.log');
const report = JSON.parse(fresh('outputs/test/reports/coverageReport.json'));
const summary = [...results.matchAll(/Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+), Ignore: (\d+)/g)];
if (summary.length !== 1) { throw new Error('Missing or ambiguous SDK test summary'); }
const [total, failures, errors, passed, ignored] = summary[0].slice(1).map(Number);
const cases = results.match(/^test=.+$/gm) ?? [];
const outcomes = [...results.matchAll(/^result=(.+)$/gm)].map(match => match[1].trim());
if (!total || failures || errors || ignored || passed !== total || cases.length !== total ||
  outcomes.length !== total || outcomes.some(result => result !== 'Success')) {
  throw new Error(`SDK assertions failed or incomplete: ${summary[0][0]}`);
}
if (!engineLog.includes('OHOS_REPORT_RESULT: stream=Tests run:') ||
  !Array.isArray(report.files) || !report.files.length || !report.summary?.lines?.covered) {
  throw new Error('Missing SDK engine completion or coverage evidence');
}
console.log(`SDK assertions passed: ${passed}/${total}; coverage lines ${report.summary.lines.pct}%`);
if (engineLog.includes('LocalSocket::')) {
  console.warn('SDK Previewer emitted LocalSocket diagnostics; raw coverage.log is retained. Assertion results above are checked separately.');
}
