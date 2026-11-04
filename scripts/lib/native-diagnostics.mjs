// Pure source inspection. Never evaluates Swift, JavaScript, SDKs, or app code.
export const RUNTIME_PATH = 'AproposMagazinev2/Services/TelemetryRuntime.swift';
const outputs = new Set(['print', 'debugPrint', 'dump', 'NSLog', 'os_logv', 'printf', 'vprintf', 'fprintf', 'vfprintf',
  'dprintf', 'vdprintf', 'fputs', 'puts', 'putchar', 'fputc', 'putc', 'fwrite', 'perror',
  'stderr', 'stdout', 'standardError', 'standardOutput', 'OSSignposter']);
const methods = new Set(['trace', 'debug', 'info', 'notice', 'warning', 'warn', 'error', 'critical', 'fault', 'log']);
const punctuation = (value) => ({kind: 'punctuation', value});
const identifier = /[A-Za-z_$][A-Za-z0-9_$]*/y;

function atLine(source, offset) {
  return source.slice(0, offset).split(/\r\n|\r|\n/).length;
}
function problem(path, source, offset, code) { return {path, line: atLine(source, offset), code}; }
function same(tokens, values) { return tokens.length === values.length && tokens.every((token, i) => token.value === values[i]); }
function closing(tokens, start, open, close) {
  let depth = 0;
  for (let index = start; index < tokens.length; index++) {
    if (tokens[index].value === open) depth++;
    else if (tokens[index].value === close && --depth === 0) return index;
  }
  return -1;
}

// Comments may be nested in Swift. Their contents never become code tokens.
function skipComment(source, start, nested, position = (offset) => offset) {
  if (source.startsWith('//', start)) {
    const next = source.indexOf('\n', start + 2);
    return next < 0 ? source.length : next;
  }
  if (!source.startsWith('/*', start)) return null;
  let depth = 1, index = start + 2;
  while (index < source.length) {
    if (nested && source.startsWith('/*', index)) { depth++; index += 2; }
    else if (source.startsWith('*/', index)) { index += 2; if (--depth === 0) return index; }
    else index++;
  }
  throw {offset: position(start)};
}

function swiftTokens(source) {
  const groups = [], strings = [];
  function code(start, interpolation = false) {
    const tokens = []; groups.push(tokens);
    let index = start, depth = interpolation ? 1 : 0;
    while (index < source.length) {
      const commentEnd = skipComment(source, index, true);
      if (commentEnd !== null) { index = commentEnd; continue; }
      if (/\s/.test(source[index])) { index++; continue; }
      const stringStart = /^(#{0,32})("""|")/.exec(source.slice(index));
      if (stringStart) {
        const position = index, hashes = stringStart[1], quotes = stringStart[2];
        const contentStart = index + stringStart[0].length;
        const endMarker = quotes + hashes, escape = '\\' + hashes;
        index = contentStart;
        const interpolations = [];
        let finished = false;
        while (index < source.length) {
          if (source.startsWith(escape, index)) {
            const next = index + escape.length;
            if (source[next] === '(') {
              const end = code(next + 1, true);
              interpolations.push([index, end]); index = end; continue;
            }
            index = Math.min(source.length, next + 1); continue;
          }
          if (source.startsWith(endMarker, index)) {
            const contentEnd = index; index += endMarker.length;
            const token = {kind: 'string', value: source.slice(position, index), start: position, end: index};
            strings.push({token, hashes, contentStart, contentEnd, before: tokens.slice(-24), interpolations});
            tokens.push(token); finished = true; break;
          }
          index++;
        }
        if (!finished) throw {offset: position};
        continue;
      }
      identifier.lastIndex = index;
      const word = identifier.exec(source);
      if (word) { tokens.push({kind: 'identifier', value: word[0], start: index}); index = identifier.lastIndex; continue; }
      const value = source[index];
      if (interpolation) {
        if (value === '(') depth++;
        if (value === ')' && --depth === 0) return index + 1;
      }
      tokens.push({...punctuation(value), start: index}); index++;
    }
    if (interpolation) throw {offset: start};
    return index;
  }
  code(0);
  return {groups, strings};
}

function runtimeAllowance(tokens) {
  const allowed = new Set(), sink = [], initializers = [];
  for (let index = 0; index < tokens.length; index++) {
    const initializer = ['let', 'logger', '=', 'Logger', '(', 'subsystem', ':', '"com.aproposmagazine.app"', ',',
      'category', ':', '"LocalDiagnostics"', ')'];
    if (same(tokens.slice(index, index + initializer.length), initializer)) initializers.push(tokens[index + 3]);
    if (!same(tokens.slice(index, index + 4), ['AppDiagnostics', '.', 'configure', '('])) continue;
    const callEnd = closing(tokens, index + 3, '(', ')');
    if (callEnd < 0) continue;
    for (let inner = index + 4; inner < callEnd; inner++) {
      if (!same(tokens.slice(inner, inner + 5), ['emit', ':', '{', 'event', 'in'])) continue;
      const blockEnd = closing(tokens, inner + 2, '{', '}');
      if (blockEnd < 0 || blockEnd > callEnd) continue;
      const body = tokens.slice(inner + 5, blockEnd);
      if (body.length === 6 && same(body.slice(0, 4), ['logger', '.', 'log', '(']) && body[4].kind === 'string' &&
          /^"\\\(event\.code,\s*privacy:\s*\.public\)"$/.test(body[4].value) && body[5].value === ')') sink.push(body[2]);
    }
  }
  if (initializers.length === 1 && sink.length === 1) {
    allowed.add(initializers[0]); allowed.add(sink[0]);
    for (let index = 0; index < tokens.length; index++) {
      if (same(tokens.slice(index, index + 2), ['import', 'OSLog'])) allowed.add(tokens[index + 1]);
    }
  }
  return {allowed, valid: initializers.length === 1 && sink.length === 1};
}

function scriptVariables(groups) {
  const names = new Set(), aliases = [];
  for (const tokens of groups) for (let index = 0; index < tokens.length; index++) {
    if (same(tokens.slice(index, index + 2), ['evaluateJavaScript', '(']) && tokens[index + 2]?.kind === 'identifier') names.add(tokens[index + 2].value);
    if (same(tokens.slice(index, index + 4), ['WKUserScript', '(', 'source', ':']) && tokens[index + 4]?.kind === 'identifier') names.add(tokens[index + 4].value);
    if (tokens[index]?.kind === 'identifier' && tokens[index + 1]?.value === '=' && tokens[index + 2]?.kind === 'identifier') {
      aliases.push([tokens[index].value, tokens[index + 2].value]);
    }
  }
  // Only follow simple local source aliases. Arbitrary runtime generation remains
  // outside a source guard's proof boundary.
  for (let changed = true; changed;) {
    changed = false;
    for (const [target, origin] of aliases) if (names.has(target) && !names.has(origin)) { names.add(origin);changed = true; }
  }
  return names;
}

function scriptContext(before, knownVariables) {
  const assignment = before.findLastIndex((token) => token.value === '=');
  if (assignment > 0 && before[assignment - 1].kind === 'identifier' &&
      (knownVariables.has(before[assignment - 1].value) || /^(?:js|javascript|script|source)$|javascript|script/i.test(before[assignment - 1].value))) return true;
  return before.some((token) => token.kind === 'identifier' && /^(?:WKUserScript|evaluateJavaScript)$/.test(token.value));
}

// Decode source-literal escapes without losing the original diagnostic location.
// This is string processing only: the resulting JavaScript is never evaluated.
function projectSwiftString(source, hashes) {
  let text = ''; const offsets = [], escape = '\\' + hashes;
  const append = (value, offset) => { text += value; for (let i = 0; i < value.length; i++) offsets.push(offset); };
  for (let index = 0; index < source.length;) {
    const start = index;
    if (!source.startsWith(escape, index)) { append(source[index++], start); continue; }
    const next = index + escape.length, char = source[next];
    const replacements = {'0': '\0', 't': '\t', 'n': '\n', 'r': '\r', '"': '"', "'": "'", '\\': '\\'};
    if (Object.hasOwn(replacements, char)) { append(replacements[char], start); index = next + 1; continue; }
    const scalar = /^u\{([0-9a-fA-F]{1,8})\}/.exec(source.slice(next));
    if (scalar) {
      const value = Number.parseInt(scalar[1], 16);
      if (value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) throw {offset: start};
      append(String.fromCodePoint(value), start);index = next + scalar[0].length;continue;
    }
    if (char === '\r' || char === '\n') { index = next + (source.startsWith('\r\n', next) ? 2 : 1);continue; }
    append(source[index++], start);
  }
  return {text, offsets};
}

function scanJavaScript(source, path, offset = 0) {
  const findings = [];
  const position = (index) => typeof offset === 'function' ? offset(index) : offset + index;
  let previous = '', index = 0;
  function code(start, templateExpression = false) {
    let depth = templateExpression ? 1 : 0;
    index = start;
    while (index < source.length) {
      const commentEnd = skipComment(source, index, false, position);
      if (commentEnd !== null) { index = commentEnd; continue; }
      const char = source[index];
      if (/\s/.test(char)) { index++; continue; }
      if (char === '"' || char === "'" || char === '`') {
        const quote = char, start = index++;
        let value = '', finished = false;
        while (index < source.length) {
          if (source[index] === '\\') { value += source.slice(index, index + 2); index += 2; continue; }
          if (quote === '`' && source.startsWith('${', index)) { code(index + 2, true); continue; }
          if (source[index] === quote) { index++; finished = true; break; }
          value += source[index++];
        }
        if (!finished) throw {offset: position(start)};
        if (previous === '[' && value === 'console') findings.push({offset: position(start), code: 'embedded_console'});
        previous = 'string'; continue;
      }
      // Ignore JavaScript regex literals, including escaped slashes/character classes.
      if (char === '/' && (!previous || ['=', '(', '[', '{', ':', ',', ';', '!', '?', 'return', '=>'].includes(previous))) {
        const start = index++; let characterClass = false, finished = false;
        while (index < source.length) {
          if (source[index] === '\\') { index += 2; continue; }
          if (source[index] === '[') characterClass = true;
          if (source[index] === ']') characterClass = false;
          if (source[index] === '/' && !characterClass) { index++;finished = true;break; }
          index++;
        }
        if (!finished) throw {offset: position(start)};
        while (/[A-Za-z]/.test(source[index] || '')) index++;
        previous = 'regex'; continue;
      }
      identifier.lastIndex = index;
      const word = identifier.exec(source);
      if (word) {
        if (word[0] === 'console') findings.push({offset: position(index), code: 'embedded_console'});
        previous = word[0];index = identifier.lastIndex;continue;
      }
      if (templateExpression) {
        if (char === '{') depth++;
        if (char === '}' && --depth === 0) { index++;return; }
      }
      previous = char;index++;
    }
    if (templateExpression) throw {offset: position(start)};
  }
  code(0);
  return findings;
}

function htmlScripts(source, start = 0) {
  const regions = [], matcher = /<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi;
  for (const match of source.matchAll(matcher)) {
    const opening = match[0].indexOf('>') + 1;
    regions.push({text: match[1], offset: start + match.index + opening});
  }
  return regions;
}

/** Static guard for ordinary app-owned callsites, not arbitrary generated/obfuscated code or SDK logging. */
export function scanNativeDiagnostics(source, {path, language = 'swift'}) {
  if (typeof source !== 'string' || typeof path !== 'string') throw new TypeError('Source and path required');
  const findings = [];
  const add = (offset, code) => findings.push(problem(path, source, offset, code));
  try {
    if (language !== 'swift') {
      const regions = language === 'html' ? htmlScripts(source) : [{text: source, offset: 0}];
      for (const region of regions) for (const finding of scanJavaScript(region.text, path, region.offset)) add(finding.offset, finding.code);
    } else {
      const {groups, strings} = swiftTokens(source);
      const knownScriptVariables = scriptVariables(groups);
      const runtime = path === RUNTIME_PATH ? runtimeAllowance(groups[0]) : {allowed: new Set(), valid: false};
      if (path === RUNTIME_PATH && !runtime.valid) add(0, 'runtime_sink_shape');
      for (const tokens of groups) for (let index = 0; index < tokens.length; index++) {
        const token = tokens[index];
        if (token.kind !== 'identifier') continue;
        const enumMember = ['print', 'debugPrint', 'dump'].includes(token.value) && tokens[index - 1]?.value === '.' &&
          tokens[index - 2]?.value !== 'Swift' && tokens[index + 1]?.value !== '(';
        if ((outputs.has(token.value) || /^os_(?:log|signpost)(?:_|$)/.test(token.value)) && !enumMember) add(token.start, 'direct_output');
        if (['Logger', 'OSLog'].includes(token.value) && !runtime.allowed.has(token)) add(token.start, 'direct_logger');
        const base = tokens[index - 2]?.value;
        const member = tokens[index - 1]?.value === '.' &&
          (tokens[index - 2]?.kind === 'identifier' || [')', ']', '?', '!'].includes(base)) && !['case', 'return', 'throw', 'if', 'guard', 'else'].includes(base);
        if (member && methods.has(token.value) && !runtime.allowed.has(token)) {
          const safePolicy = token.value === 'error' && base === 'TelemetryDiagnosticPolicy';
          const safeHaptic = token.value === 'error' && same(tokens.slice(index - 4, index), ['HapticManager', '.', 'shared', '.']);
          if (!safePolicy && !safeHaptic) add(token.start, 'direct_log_method');
        }
      }
      for (const literal of strings) {
        let content = source.slice(literal.contentStart, literal.contentEnd);
        for (const [start, end] of [...literal.interpolations].reverse()) {
          const left = start - literal.contentStart, right = end - literal.contentStart;
          content = content.slice(0, left) + content.slice(left, right).replace(/[^\r\n]/g, ' ') + content.slice(right);
        }
        const projected = projectSwiftString(content, literal.hashes);
        const regions = htmlScripts(projected.text);
        if (!regions.length && scriptContext(literal.before, knownScriptVariables)) regions.push({text: projected.text, offset: 0});
        for (const region of regions) {
          const locate = (index) => literal.contentStart + (projected.offsets[region.offset + index] ?? content.length);
          for (const finding of scanJavaScript(region.text, path, locate)) add(finding.offset, finding.code);
        }
      }
    }
  } catch (error) {
    add(Number.isInteger(error?.offset) ? Math.max(0, Math.min(error.offset, source.length)) : 0, 'source_lexical_error');
  }
  const unique = new Map(findings.map((finding) => [`${finding.line}:${finding.code}`, finding]));
  return [...unique.values()].sort((left, right) => left.line - right.line || left.code.localeCompare(right.code));
}

export function formatFinding({path, line, code}) {
  // JSON quoting prevents a pathological filename from injecting extra log lines.
  return `${JSON.stringify(path)}:${line} [${code}]`;
}
