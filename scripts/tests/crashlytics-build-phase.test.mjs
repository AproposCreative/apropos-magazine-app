import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

const project = readFileSync(new URL('../../AproposMagazinev2.xcodeproj/project.pbxproj', import.meta.url), 'utf8');
const phase = project.slice(project.indexOf('/* Crashlytics dSYM Upload */ = {'));
const literal = phase.match(/shellScript = ("(?:\\.|[^"\\])*");/)[1];
const script = JSON.parse(literal);

function run({optIn, platform = 'iphoneos', signing = 'YES', dsym = true}) {
  const root = mkdtempSync(join(tmpdir(), 'apropos-symbol-guard-'));
  try {
    const sdk = join(root, 'SourcePackages/checkouts/firebase-ios-sdk/Crashlytics');
    mkdirSync(sdk, {recursive: true});
    const marker = join(root, 'called');
    // Only a local marker is possible; the Firebase tool is never executed.
    writeFileSync(join(sdk, 'run'), '#!/bin/sh\nprintf called > "$TEST_MARKER"\n', {mode: 0o700});
    if (dsym) mkdirSync(join(root, 'symbols/App.dSYM'), {recursive: true});
    const env = {PATH: '/usr/bin:/bin', PLATFORM_NAME: platform, CODE_SIGNING_ALLOWED: signing,
      DWARF_DSYM_FOLDER_PATH: join(root, 'symbols'), DWARF_DSYM_FILE_NAME: 'App.dSYM',
      BUILD_DIR: join(root, 'Build/Products'), TEST_MARKER: marker};
    if (optIn !== undefined) env.APROPOS_CRASHLYTICS_UPLOAD = optIn;
    const result = spawnSync('/bin/sh', ['-c', script], {env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return {called: existsSync(marker), output: result.stdout};
  } finally { rmSync(root, {recursive: true, force: true}); }
}

for (const optIn of [undefined, '', 'NO', 'yes']) {
  test(`signed archive with dSYM has no upload for ${String(optIn)}`, () => {
    const result = run({optIn});
    assert.equal(result.called, false);
    assert.match(result.output, /symbol upload disabled/);
  });
}
test('explicit YES still excludes simulator', () => assert.equal(run({optIn: 'YES', platform: 'iphonesimulator'}).called, false));
test('explicit YES still excludes unsigned build', () => assert.equal(run({optIn: 'YES', signing: 'NO'}).called, false));
test('explicit YES still requires actual dSYM', () => assert.equal(run({optIn: 'YES', dsym: false}).called, false));
test('explicit YES with signed device and dSYM reaches only injected local stub', () => assert.equal(run({optIn: 'YES'}).called, true));
