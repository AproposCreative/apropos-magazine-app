#!/usr/bin/env node
// Reads source only; never imports the app, SDKs, credentials or generated builds.
import {readdir, readFile} from 'node:fs/promises';
import {fileURLToPath, pathToFileURL} from 'node:url';
import path from 'node:path';
import {scanNativeDiagnostics, formatFinding} from './lib/native-diagnostics.mjs';

export async function scanAppDirectory(directory) {
  const findings = [];let files = 0;
  async function walk(current, relative = '') {
    let entries;
    try { entries = await readdir(current, {withFileTypes: true}); }
    catch { findings.push({path: `AproposMagazinev2/${relative}`, line: 1, code: 'source_read_failed'});return; }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const name = path.posix.join(relative, entry.name), display = `AproposMagazinev2/${name}`, absolute = path.join(current, entry.name);
      if (entry.isSymbolicLink()) { findings.push({path: display, line: 1, code: 'source_symlink'});continue; }
      if (entry.isDirectory()) { await walk(absolute, name);continue; }
      if (!entry.isFile() || !/\.(swift|m|mm|h|js|html)$/i.test(entry.name)) continue;
      let source;
      try { source = await readFile(absolute, 'utf8'); }
      catch { findings.push({path: display, line: 1, code: 'source_read_failed'});continue; }
      files++;
      const language = /\.js$/i.test(entry.name) ? 'javascript' : /\.html$/i.test(entry.name) ? 'html' : 'swift';
      findings.push(...scanNativeDiagnostics(source, {path: display, language}));
    }
  }
  await walk(directory);
  return {files, findings};
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  const directory = fileURLToPath(new URL('../AproposMagazinev2', import.meta.url));
  const result = await scanAppDirectory(directory);
  for (const finding of result.findings) process.stderr.write(formatFinding(finding) + '\n');
  process.stdout.write(`Native diagnostics source guard: ${result.files} files, ${result.findings.length} findings.\n`);
  process.exitCode = result.findings.length ? 1 : 0;
}
