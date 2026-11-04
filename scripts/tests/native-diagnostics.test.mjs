import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, symlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {scanNativeDiagnostics, formatFinding, RUNTIME_PATH} from '../lib/native-diagnostics.mjs';
import {scanAppDirectory} from '../native-diagnostics-check.mjs';

const fixturePath = 'AproposMagazinev2/Views/Fixture.swift';
const scan = (source, options = {}) => scanNativeDiagnostics(source, {path: fixturePath, ...options});
const runtime = String.raw`import Foundation
import OSLog
let logger = Logger(subsystem: "com.aproposmagazine.app", category: "LocalDiagnostics")
AppDiagnostics.configure(model: model, storage: storage, emit: { event in
    // The sink receives a policy-approved event inside the existing ticket gate.
    logger.log("\(event.code, privacy: .public)")
}, now: clock)
`;

test('ordinary global output APIs and references cannot bypass the local trail', () => {
  for (const api of ['print', 'debugPrint', 'dump', 'NSLog', 'os_log', 'os_logv', 'os_log_with_type', 'os_signpost', 'os_signpost_event_emit',
    'printf', 'vprintf', 'fprintf', 'vfprintf', 'fputs', 'puts', 'putchar', 'fwrite', 'perror']) {
    assert.ok(scan(`${api}("private token")`).some((item) => item.code === 'direct_output'), api);
  }
  assert.ok(scan('let output = Swift.print').some((item) => item.code === 'direct_output'));
});

test('stderr and FileHandle outputs are rejected without inspecting their payloads', () => {
  for (const source of ['fputs(secret, stderr)', 'FileHandle.standardError.write(data)', 'FileHandle.standardOutput.write(data)', 'let output = stdout']) {
    assert.ok(scan(source).some((item) => item.code === 'direct_output'));
  }
});

test('Logger imports, aliases, type references and signpost construction are rejected', () => {
  for (const source of ['import OSLog', 'let alternate = Logger(subsystem: value, category: value)', 'let old = OSLog.default',
    'let type = Logger.self', 'let signposter = OSSignposter()']) assert.ok(scan(source).length > 0, source);
});

test('log method calls remain forbidden under alternate receiver names and multiple lines', () => {
  for (const method of ['log', 'debug', 'info', 'warning', 'error', 'critical', 'fault', 'trace', 'notice', 'warn']) {
    assert.ok(scan(`sink\n .\n ${method}\n ("private")`).some((item) => item.code === 'direct_log_method'), method);
  }
});

test('optional receivers, forced receivers and method references cannot hide output behind an alias', () => {
  for (const source of ['sink?.error(secret)', 'sink!.warning(secret)', 'let emit = sink.error\nemit(secret)',
    'let emit = sink?.log', 'factory().debug(secret)', 'sinks[0].info(secret)']) {
    assert.ok(scan(source).some((item) => item.code === 'direct_log_method'), source);
  }
});

test('line and nested Swift comments cannot create false callsites', () => {
  assert.deepEqual(scan(`// print(secret)\n/* Logger() /* NSLog(secret) */ logger.error(secret) */\nlet safe = 1`), []);
});

test('normal quoted, raw and multiline display strings are not executable native logs', () => {
  assert.deepEqual(scan(String.raw`let message = "Logger() and print(secret) and console.error(secret)"
let example = #"NSLog(secret), \(print(secret))"#
let help = """
Documentation mentions logger.error(secret) and console.error(secret).
"""`), []);
});

test('Swift string interpolation is real code even inside a displayed string', () => {
  const findings = scan(String.raw`let message = "value \(print(secret))"`);
  assert.equal(findings.length, 1);assert.equal(findings[0].code, 'direct_output');
});

test('raw Swift interpolation and multiline interpolation retain original source lines', () => {
  const findings = scan(String.raw`let message = #"""
value
\#(NSLog("private"))
"""#`);
  assert.deepEqual(findings, [{path: fixturePath, line: 3, code: 'direct_output'}]);
});

test('multiline embedded JavaScript calls are rejected at the console source line', () => {
  const findings = scan('let js = """\nconsole\n .\n error("private");\n"""');
  assert.deepEqual(findings, [{path: fixturePath, line: 2, code: 'embedded_console'}]);
});

test('raw script literals and bracket notation cannot hide the console object', () => {
  for (const body of ['console.error(secret)', 'window.console["warn"](secret)', 'globalThis["console"]["log"](secret)']) {
    assert.ok(scan(`let javaScript = #"${body.replaceAll('"', "'")}"#`).some((item) => item.code === 'embedded_console'));
  }
});

test('JavaScript comments, strings, template text and regex literal mentions are ignored', () => {
  const source = String.raw`let js = #"""
// console.error(secret)
/* console.warn(secret) */
const quoted = "console.error(secret)";
const regex = /console\.error\(secret\)/;
const label = ` + '`console.error(secret)`;' + '\n"""#';
  assert.deepEqual(scan(source), []);
});

test('JavaScript template interpolations remain executable code', () => {
  const source = 'let script = #"""\nconst label = `text ${console.warn(secret)}`;\n"""#';
  assert.ok(scan(source).some((item) => item.code === 'embedded_console'));
});

test('evaluateJavaScript argument literals are inspected without running the JavaScript', () => {
  assert.ok(scan('webView.evaluateJavaScript("console.error(secret)")').some((item) => item.code === 'embedded_console'));
});

test('an innocuously named literal and simple aliases are traced to real WebKit source arguments', () => {
  for (const source of ['let payload = "console.error(secret)"\nwebView.evaluateJavaScript(payload)',
    'let payload = "console.error(secret)"\nlet alias = payload\nlet item = WKUserScript(source: alias, injectionTime: .atDocumentEnd, forMainFrameOnly: true)']) {
    assert.deepEqual(scan(source), [{path: fixturePath, line: 1, code: 'embedded_console'}]);
  }
  assert.deepEqual(scan('let payload = "console.error(secret)"\nText(payload)'), []);
});

test('ordinary Swift escapes preserve harmless JavaScript strings and the original finding line', () => {
  assert.deepEqual(scan(String.raw`let js = "const label = \"console.error(secret)\";"`), []);
  const source = String.raw`let js = "const label = \"safe\";\nconsole.error(secret);"`;
  assert.deepEqual(scan(source), [{path: fixturePath, line: 1, code: 'embedded_console'}]);
  const multiline = String.raw`let js = """
const label = "safe";
con\u{0073}ole.error(secret);
"""`;
  assert.deepEqual(scan(multiline), [{path: fixturePath, line: 3, code: 'embedded_console'}]);
});

test('raw Swift escapes only decode when their delimiter hash matches', () => {
  assert.deepEqual(scan(String.raw`let js = #"const label = "console.error(secret)";"#`), []);
  assert.deepEqual(scan(String.raw`let js = #"con\#u{0073}ole.error(secret)"#`),
    [{path: fixturePath, line: 1, code: 'embedded_console'}]);
});

test('HTML only inspects script elements and ignores display text', () => {
  const source = 'let html = """\n<p>console.error(secret)</p>\n<script>console.error(secret)</script>\n"""';
  assert.deepEqual(scan(source), [{path: fixturePath, line: 3, code: 'embedded_console'}]);
  assert.deepEqual(scan('<p>console.error(secret)</p>', {language: 'html'}), []);
});

test('standalone JavaScript source uses the same console guard', () => {
  assert.deepEqual(scan('/* console.log("ignored") */\nconsole.error(secret)', {language: 'javascript'}),
    [{path: fixturePath, line: 2, code: 'embedded_console'}]);
});

test('the exact approved Runtime initializer and event-code-only configured sink are accepted', () => {
  assert.deepEqual(scan(runtime, {path: RUNTIME_PATH}), []);
});

test('moving the same sink to another file cannot inherit Runtime approval', () => {
  for (const file of [fixturePath, 'Other/' + RUNTIME_PATH, 'AproposMagazinev2/Services/TelemetryRuntimeCopy.swift']) {
    assert.ok(scan(runtime, {path: file}).some((item) => item.code === 'direct_logger'));
  }
});

test('the Runtime file is not a blanket exemption for extra or changed logs', () => {
  for (const source of [runtime + '\nlogger.error(secret)', runtime.replace('event.code', 'event.payload'),
    runtime.replace('"LocalDiagnostics"', 'secret'), runtime.replace('let logger', 'var logger'),
    runtime.replace('emit: { event in', 'other: { event in')]) {
    assert.ok(scan(source, {path: RUNTIME_PATH}).length > 0);
  }
});

test('a copied log outside AppDiagnostics.configure cannot impersonate the guarded sink', () => {
  const source = runtime.replace('AppDiagnostics.configure(model: model, storage: storage, emit: { event in', 'func unsafe(event: Event) {').replace('}, now: clock)', '}');
  assert.ok(scan(source, {path: RUNTIME_PATH}).some((item) => item.code === 'runtime_sink_shape'));
});

test('the approved sink cannot include raw parameters, a second log or a dynamic logger', () => {
  for (const source of [runtime.replace('event.code, privacy: .public', 'event.code, privacy: .private'),
    runtime.replace('logger.log(', 'logger.error('), runtime.replace('logger.log(', 'logger.log(secret); logger.log('),
    runtime.replace('"com.aproposmagazine.app"', '"\\(secret)"')]) assert.ok(scan(source, {path: RUNTIME_PATH}).length > 0);
});

test('nonlogging enum values, error cases, haptics and sanitized error projection remain valid', () => {
  assert.deepEqual(scan('let excluded = [UIActivity.ActivityType.print, .print]\ncase .error(let message): break\nHapticManager.shared.error()\nTelemetryDiagnosticPolicy.error(context: context)'), []);
});

test('unclosed comments, native strings and script strings fail closed', () => {
  for (const source of ['/* not closed', 'let text = "not closed', 'let js = #"""\nconst text = "unterminated\n"""#']) {
    assert.ok(scan(source).some((item) => item.code === 'source_lexical_error'));
  }
});

test('unclosed JavaScript comments report original Swift and HTML source coordinates', () => {
  const cases = [
    {source: 'let js = """\nconst value = 1;\n/* unterminated\n"""', line: 3},
    {source: String.raw`let js = "const value = 1;\n/* unterminated"`, line: 1},
    {source: 'let html = """\n<p>Display text</p>\n<script>\nconst value = 1;\n/* unterminated\n</script>\n"""', line: 5},
    {source: '<p>Display text</p>\n<script>\n/* unterminated\n</script>', language: 'html', line: 3},
    {source: 'const value = 1;\n/* unterminated', language: 'javascript', line: 2},
    {source: 'let value = 1\n\n/* unterminated', line: 3}
  ];
  for (const {source, language, line} of cases) {
    assert.deepEqual(scan(source, language ? {language} : {}), [{path: fixturePath, line, code: 'source_lexical_error'}]);
  }
});

test('findings contain only path, line and controlled codes, never source arguments or thrown details', () => {
  const findings = scan('let token = "sensitive-value"\nNSLog("https://private.invalid?token=hidden")');
  assert.deepEqual(Object.keys(findings[0]).sort(), ['code', 'line', 'path']);
  assert.equal(findings[0].line, 2);
  assert.doesNotMatch(JSON.stringify(findings), /sensitive|private|hidden/);
  assert.doesNotMatch(formatFinding(findings[0]), /sensitive|private|hidden/);
  const formatted = formatFinding({path: 'Views/line\nbreak.swift', line: 3, code: 'direct_output'});
  assert.equal(formatted.split('\n').length, 1);assert.match(formatted, /\\n/);
});

test('directory traversal covers nested app, view, widget, extension and JavaScript source without imports', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'apropos-log-guard.'));
  try {
    for (const name of ['Views/Screen.swift', 'ViewModels/Model.swift', 'AproposMagazineWidget/Widget.swift', 'AproposMagazineNotificationService/Extension.swift']) {
      await mkdir(path.dirname(path.join(directory, name)), {recursive: true});await writeFile(path.join(directory, name), 'NSLog(secret)');
    }
    await writeFile(path.join(directory, 'reader.js'), 'console.log(secret)');
    await writeFile(path.join(directory, 'reader.html'), '<script>console.warn(secret)</script>');
    await writeFile(path.join(directory, 'not-code.txt'), 'print(secret)');
    const result = await scanAppDirectory(directory);
    assert.equal(result.files, 6);assert.equal(result.findings.length, 6);
    assert.ok(result.findings.some((item) => item.path.includes('AproposMagazineNotificationService')));
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('a missing directory or source symlink is a static failure instead of skipped coverage', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'apropos-log-guard.'));
  try {
    await symlink(path.join(directory, 'missing.swift'), path.join(directory, 'alias.swift'));
    assert.equal((await scanAppDirectory(directory)).findings[0].code, 'source_symlink');
    assert.equal((await scanAppDirectory(path.join(directory, 'missing'))).findings[0].code, 'source_read_failed');
  } finally { await rm(directory, {recursive: true, force: true}); }
});
