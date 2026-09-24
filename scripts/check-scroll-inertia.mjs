#!/usr/bin/env node
// 1.3: two-finger scroll coasting must see the commit flag from before it is cleared.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(join(root, 'MagicPadClient/index.html'), 'utf8');
const m = html.match(/function magicpadScrollInertia\(scrollWasCommitted, rightFired, velX, velY\) \{\n([\s\S]*?)\n    \}/);
if (!m) {
  console.error('missing magicpadScrollInertia');
  process.exit(1);
}
const magicpadScrollInertia = new Function(
  'scrollWasCommitted', 'rightFired', 'velX', 'velY',
  m[1]
);

const cases = [
  ['committed flick', true, false, 4, -0.2, true],
  ['committed flick up', true, false, 0, -2, true],
  ['right click', true, true, 8, 8, false],
  ['not a scroll', false, false, 8, 0, false],
  ['stopped', true, false, 1.5, -1.5, false],
  ['just over', true, false, 1.51, 0, true],
  ['cleared flag', false, false, 9, 9, false],
];

let failed = 0;
for (const [name, committed, right, vx, vy, want] of cases) {
  const got = magicpadScrollInertia(committed, right, vx, vy);
  if (got !== want) {
    failed++;
    console.error('FAIL', name, 'got', got, 'want', want);
  }
}

// The old bug: test the flag after assigning false. That must not coast.
if (magicpadScrollInertia(false, false, 6, 6) !== false) {
  failed++;
  console.error('FAIL cleared flag still coasts');
}

function branchOrder(label) {
  let from = 0;
  let seen = 0;
  while (from < html.length) {
    const snap = html.indexOf('const scrollWasCommitted = twoFingerScrollCommitted;', from);
    if (snap < 0) break;
    seen++;
    const clear = html.indexOf('twoFingerScrollCommitted = false;', snap);
    const call = html.indexOf('magicpadScrollInertia(scrollWasCommitted', snap);
    if (clear < 0 || call < 0 || !(snap < clear && clear < call) || call - snap > 1800) {
      failed++;
      console.error('FAIL', label, 'snapshot/clear/call order at', snap);
      return;
    }
    from = call + 10;
  }
  if (seen !== 2) {
    failed++;
    console.error('FAIL expected 2 inertia snapshots, got', seen);
  }
}
branchOrder('order');

if (!html.includes("var MAGICPAD_HTML_REV = '20260924-1.3-h819'")) {
  failed++;
  console.error('FAIL htmlRev');
}

if (failed) process.exit(1);
console.log('SCROLL_INERTIA_OK');
