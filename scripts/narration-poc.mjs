#!/usr/bin/env node
/**
 * Proof-of-concept: AI-oplæsning af ÉN artikel (Robin Hood) med ElevenLabs.
 *
 * Henter artiklen direkte fra Webflow (self-contained, kræver ikke gcloud/Firestore),
 * slår forfatternavn op, bygger en talt intro + ren artikeltekst + outro, kalder
 * ElevenLabs (stemme "Ellen", model eleven_v3), og gemmer en lokal .m4a man kan lytte til.
 *
 * Ingen upload — ren test af stemme/kvalitet før resten af pipelinen bygges.
 *
 * Kræver i .env (projektroden):
 *   WEBFLOW_API_KEY=...
 *   ELEVENLABS_API_KEY=...
 *   (valgfri) ELEVENLABS_VOICE_NAME=Ellen   eller   ELEVENLABS_VOICE_ID=...
 *   (valgfri) ELEVENLABS_MODEL_ID=eleven_v3
 *
 * Brug:
 *   node scripts/narration-poc.mjs
 *   node scripts/narration-poc.mjs --slug=the-death-of-robin-hood-review
 *   node scripts/narration-poc.mjs --text-only   (spring TTS over, vis kun teksten)
 */

import { spawn } from 'node:child_process';
import { execSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, statSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');

// ---- Load .env from repo root (Node >= 20.12) -----------------------------
try {
  process.loadEnvFile(join(repoRoot, '.env'));
} catch {
  // Ignore — env vars may already be set in the shell.
}

// ---- Config ---------------------------------------------------------------
const ARTICLES_COLLECTION_ID = '67dbf17ba540975b5b21c2a6';
const AUTHORS_COLLECTION_ID = '67dbf17ba540975b5b21c294';
const WEBFLOW_PAGE_LIMIT = 100;

const VOICE_NAME = process.env.ELEVENLABS_VOICE_NAME || 'Ellen';
const VOICE_ID_OVERRIDE = process.env.ELEVENLABS_VOICE_ID || '';
const MODEL_ID = process.env.ELEVENLABS_MODEL_ID || 'eleven_v3';
const OUTPUT_FORMAT = 'mp3_44100_128';
// v3 har lavere tegngrænse pr. kald end multilingual_v2.
const MAX_CHARS_PER_CHUNK = MODEL_ID === 'eleven_v3' ? 2800 : 9000;

const TARGET_BITRATE = '128k';
const TARGET_SAMPLE_RATE = '44100';

const args = process.argv.slice(2);
function argValue(name, fallback) {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : fallback;
}
const SLUG = argValue('slug', 'the-death-of-robin-hood-review');
const TEXT_ONLY = args.includes('--text-only');
// Re-encode fra cachet rå-lyd UDEN at kalde ElevenLabs igen (sparer credits ved lyd-finjustering).
const REENCODE = args.includes('--reencode');
// Afspilningshastighed via ffmpeg atempo: 1.0 = ingen ændring (matcher playground).
// OBS: atempo tids-strækker og kan forringe kvaliteten — hold den på 1.0 medmindre nødvendigt.
const SPEED = parseFloat(argValue('speed', process.env.NARRATION_SPEED || '1.0'));
// Valgfri blød diskant-dæmpning i dB (negativ = mindre skarp), fx --treble=-2
const TREBLE_GAIN = parseFloat(argValue('treble', process.env.NARRATION_TREBLE || '0'));
// Valgfri baggrundsjingle der loopes under oplæsningen og dæmpes (dB).
// Default: committet repo-asset, så backfill/regenerering lyder identisk uden ekstra flag.
const DEFAULT_JINGLE = join(repoRoot, 'scripts', 'assets', 'narration-jingle.wav');
const JINGLE_PATH = argValue(
  'jingle',
  process.env.NARRATION_JINGLE || (existsSync(DEFAULT_JINGLE) ? DEFAULT_JINGLE : '')
);
const JINGLE_GAIN = argValue('jingle-gain', process.env.NARRATION_JINGLE_GAIN || '-18'); // dB
const JINGLE_FADE_IN = parseFloat(argValue('jingle-fade-in', '1'));
const JINGLE_FADE_OUT = parseFloat(argValue('jingle-fade-out', '3'));
// Musik-intro: antal sekunder hvor musikken er højere, før stemmen begynder.
const JINGLE_INTRO_SECS = parseFloat(argValue('jingle-intro', process.env.NARRATION_JINGLE_INTRO || '6'));
// Niveau på musikken under intro-delen (dB), før den fader ned til bed-niveau (JINGLE_GAIN).
const JINGLE_INTRO_GAIN = argValue('jingle-intro-gain', process.env.NARRATION_JINGLE_INTRO_GAIN || '-5');
// Hvor hurtigt musikken dukker fra intro-niveau til bed-niveau (sek).
const JINGLE_DUCK = parseFloat(argValue('jingle-duck', '1.5'));

// "Stemme-polish": blød EQ der dæmper hård diskant/sibilance og tilfører lidt varme.
// Slå fra med --no-polish.
const POLISH = !args.includes('--no-polish');
// Stereo-output med let bredde (rundere lyd). Slå fra med --mono.
const STEREO_OUT = !args.includes('--mono');
const OUT_CHANNELS = STEREO_OUT ? '2' : '1';
// Override af stemmens voice_settings. Default: TOM = brug stemmens egne (som playground).
// Aktivér fx med ELEVENLABS_VOICE_SETTINGS='{"stability":0.5,"similarity_boost":0.75}'
const VOICE_SETTINGS_OVERRIDE = (() => {
  const raw = (process.env.ELEVENLABS_VOICE_SETTINGS || '').trim();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
})();

const outDir = join(repoRoot, 'podcast-audio', 'poc');

// ---- Helpers --------------------------------------------------------------
function requireEnv(name) {
  const value = (process.env[name] || '').trim();
  if (!value) {
    console.error(`\nMangler ${name} i .env (projektroden: ${join(repoRoot, '.env')}).`);
    process.exit(1);
  }
  return value;
}

function decodeEntities(text) {
  const named = {
    amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
    aelig: 'æ', AElig: 'Æ', oslash: 'ø', Oslash: 'Ø', aring: 'å', Aring: 'Å',
    eacute: 'é', egrave: 'è', uuml: 'ü', ouml: 'ö', auml: 'ä',
    hellip: '…', mdash: '—', ndash: '–', lsquo: '‘', rsquo: '’',
    ldquo: '“', rdquo: '”', laquo: '«', raquo: '»', deg: '°', euro: '€',
  };
  return text
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&([a-zA-Z]+);/g, (m, name) => (name in named ? named[name] : m));
}

function htmlToReadableText(html) {
  if (!html) return '';
  let text = String(html);
  // Drop elements whose visible text we don't want spoken.
  text = text.replace(/<figcaption[\s\S]*?<\/figcaption>/gi, ' ');
  text = text.replace(/<figure[\s\S]*?<\/figure>/gi, ' ');
  text = text.replace(/<script[\s\S]*?<\/script>/gi, ' ');
  text = text.replace(/<style[\s\S]*?<\/style>/gi, ' ');
  text = text.replace(/<iframe[\s\S]*?<\/iframe>/gi, ' ');
  // Turn block-level boundaries into paragraph breaks.
  text = text.replace(/<\/(p|div|h[1-6]|li|blockquote|tr|section|article)>/gi, '\n\n');
  text = text.replace(/<br\s*\/?>/gi, '\n');
  // Strip the rest of the tags.
  text = text.replace(/<[^>]+>/g, ' ');
  text = decodeEntities(text);
  // Normalise whitespace.
  text = text.replace(/[ \t\u00a0]+/g, ' ');
  text = text.replace(/ *\n */g, '\n');
  text = text.replace(/\n{3,}/g, '\n\n');
  return text.trim();
}

function chunkText(text, maxChars) {
  // Split on paragraph/sentence boundaries so chunks stay under the model limit.
  const paragraphs = text.split(/\n{2,}/);
  const chunks = [];
  let current = '';

  const pushCurrent = () => {
    if (current.trim()) chunks.push(current.trim());
    current = '';
  };

  for (const para of paragraphs) {
    if ((current + '\n\n' + para).length <= maxChars) {
      current = current ? `${current}\n\n${para}` : para;
      continue;
    }
    pushCurrent();
    if (para.length <= maxChars) {
      current = para;
      continue;
    }
    // Paragraph itself too long → split on sentences.
    const sentences = para.match(/[^.!?]+[.!?]+|\S+$/g) || [para];
    for (const sentence of sentences) {
      if ((current + ' ' + sentence).length <= maxChars) {
        current = current ? `${current} ${sentence}` : sentence;
      } else {
        pushCurrent();
        current = sentence.trim();
      }
    }
  }
  pushCurrent();
  return chunks;
}

async function webflowGet(url) {
  const apiKey = requireEnv('WEBFLOW_API_KEY');
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'accept-version': '1.0.0',
    },
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Webflow ${response.status}: ${body}`);
  }
  return response.json();
}

async function findArticleBySlug(slug) {
  let offset = 0;
  while (true) {
    const url =
      `https://api.webflow.com/v2/collections/${ARTICLES_COLLECTION_ID}/items` +
      `?live=true&limit=${WEBFLOW_PAGE_LIMIT}&offset=${offset}` +
      `&sortBy=lastPublished&sortOrder=desc`;
    const payload = await webflowGet(url);
    const items = Array.isArray(payload.items) ? payload.items : [];
    const match = items.find((it) => (it.fieldData?.slug || '') === slug);
    if (match) return match;
    if (items.length < WEBFLOW_PAGE_LIMIT) return null;
    offset += WEBFLOW_PAGE_LIMIT;
  }
}

async function resolveAuthorName(authorId) {
  if (!authorId) return '';
  try {
    const url =
      `https://api.webflow.com/v2/collections/${AUTHORS_COLLECTION_ID}/items/${authorId}/live`;
    const payload = await webflowGet(url);
    return String(payload.fieldData?.name || '').trim();
  } catch {
    return '';
  }
}

async function resolveVoiceId(apiKey) {
  if (VOICE_ID_OVERRIDE) return VOICE_ID_OVERRIDE;
  const response = await fetch('https://api.elevenlabs.io/v1/voices', {
    headers: { 'xi-api-key': apiKey },
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`ElevenLabs /v1/voices ${response.status}: ${body}`);
  }
  const data = await response.json();
  const voices = Array.isArray(data.voices) ? data.voices : [];
  const wanted = VOICE_NAME.trim().toLowerCase();
  // ElevenLabs-stemmer hedder ofte "Ellen - Serious, Direct and Confident".
  // Match på fuldt navn, præfiks ("Ellen - ...") eller første ord.
  const match =
    voices.find((v) => String(v.name || '').trim().toLowerCase() === wanted) ||
    voices.find((v) => String(v.name || '').trim().toLowerCase().startsWith(`${wanted} -`)) ||
    voices.find((v) => String(v.name || '').trim().toLowerCase().split(/\s+/)[0] === wanted);
  if (!match) {
    const names = voices.map((v) => v.name).join(', ');
    throw new Error(`Fandt ikke stemmen "${VOICE_NAME}". Tilgængelige: ${names || '(ingen)'}`);
  }
  console.log('valgt stemme:', match.name);
  return match.voice_id;
}

async function synthesizeChunk(apiKey, voiceId, text, outPath) {
  const body = {
    text,
    model_id: MODEL_ID,
  };
  // Default: ingen voice_settings → brug stemmens egne (som playground). Kun override hvis sat.
  if (VOICE_SETTINGS_OVERRIDE) body.voice_settings = VOICE_SETTINGS_OVERRIDE;
  // multilingual_v2 understøtter language_code; v3 auto-detekterer.
  if (MODEL_ID.includes('multilingual')) body.language_code = 'da';

  const url =
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=${OUTPUT_FORMAT}`;

  const maxAttempts = 3;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
        },
        body: JSON.stringify(body),
      });
      if (!response.ok) {
        const errText = await response.text();
        // 4xx (fx betaling/forkert input) nytter ikke at gentage.
        if (response.status >= 400 && response.status < 500) {
          throw new Error(`ElevenLabs TTS ${response.status}: ${errText}`);
        }
        throw new Error(`ElevenLabs TTS ${response.status}: ${errText} (forsøg ${attempt})`);
      }
      const buffer = Buffer.from(await response.arrayBuffer());
      writeFileSync(outPath, buffer);
      return buffer.length;
    } catch (err) {
      lastError = err;
      if (String(err.message).match(/ TTS 4\d\d:/)) throw err; // permanent fejl
      if (attempt < maxAttempts) {
        const waitMs = attempt * 2000;
        process.stdout.write(`(netværksfejl, prøver igen om ${waitMs / 1000}s) `);
        await new Promise((r) => setTimeout(r, waitMs));
      }
    }
  }
  throw lastError;
}

function requireFfmpeg() {
  try {
    execSync('ffmpeg -version', { stdio: 'ignore' });
  } catch {
    console.error('ffmpeg ikke fundet. Installer: brew install ffmpeg');
    process.exit(1);
  }
}

// Saml chunks + kod i ÉT pass (gen-koder → rene tidsstempler, ingen dts-klik).
// Let efterbehandling: kun fart (toneleje bevaret) + valgfri blød diskant-dæmpning.
// Ingen aggressiv loudness-normalisering — ElevenLabs-lyden bevares tæt på originalen.
function voiceFilterChain() {
  const filters = [];
  if (SPEED && SPEED !== 1) filters.push(`atempo=${SPEED}`);
  if (POLISH) {
    // Lidt varme i bunden:
    filters.push('equalizer=f=180:t=q:w=1.0:g=2');
    // Dæmp "honk"/nasal i mellemtonen:
    filters.push('equalizer=f=3200:t=q:w=2.0:g=-1.5');
    // Dæmp hård sibilance/diskant der gør ondt i ørerne:
    filters.push('equalizer=f=7200:t=q:w=2.5:g=-4');
    // Skær det allerøverste skarpe væk:
    filters.push('lowpass=f=15000');
  }
  if (TREBLE_GAIN && TREBLE_GAIN !== 0) filters.push(`treble=g=${TREBLE_GAIN}:f=6500`);
  // Mono → blød stereobredde (rundere lyd). Haas konverterer mono til stereo.
  // Lav side_gain = mindre bredde (mere fokuseret).
  if (STEREO_OUT) filters.push('haas=side_gain=0.3');
  return filters;
}

// Saml chunks + kod stemmen. wav=true → lossless mellem-fil (bruges når der mixes jingle på).
function encodeFromList(listPath, outPath, { wav = false } = {}) {
  return new Promise((resolvePromise, reject) => {
    const filters = voiceFilterChain();
    const ffArgs = [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'concat', '-safe', '0', '-i', listPath,
    ];
    if (filters.length) ffArgs.push('-af', filters.join(','));
    ffArgs.push('-ar', TARGET_SAMPLE_RATE, '-ac', OUT_CHANNELS);
    if (wav) {
      ffArgs.push('-c:a', 'pcm_s16le', outPath);
    } else {
      ffArgs.push('-c:a', 'aac', '-b:a', TARGET_BITRATE, '-movflags', '+faststart', outPath);
    }
    const ff = spawn('ffmpeg', ffArgs, { stdio: 'inherit' });
    ff.on('error', reject);
    ff.on('close', (code) => (code === 0 ? resolvePromise() : reject(new Error(`ffmpeg encode exit ${code}`))));
  });
}

function probeDuration(path) {
  const out = execSync(
    `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${path}"`,
  ).toString().trim();
  return parseFloat(out) || 0;
}

function dbToLinear(db) {
  return Math.pow(10, parseFloat(db) / 20);
}

// Musik-intro (højere) der dukker ned til bed-niveau, hvorefter stemmen begynder.
// Stemmen forsinkes med JINGLE_INTRO_SECS; jinglen loopes under hele oplæsningen og fader ud til sidst.
function mixJingle(voicePath, jinglePath, outPath, voiceDuration) {
  return new Promise((resolvePromise, reject) => {
    const introLin = dbToLinear(JINGLE_INTRO_GAIN);
    const bedLin = dbToLinear(JINGLE_GAIN);
    const duckStart = JINGLE_INTRO_SECS;
    const duckEnd = JINGLE_INTRO_SECS + JINGLE_DUCK;
    const total = voiceDuration + JINGLE_INTRO_SECS;
    const fadeOutStart = Math.max(0, total - JINGLE_FADE_OUT);

    // Lydstyrke-kurve for musikken: intro-niveau → lineær ramp ned → bed-niveau.
    const duckExpr =
      `if(lt(t,${duckStart}),${introLin.toFixed(4)},` +
      `if(lt(t,${duckEnd}),${introLin.toFixed(4)}+(${bedLin.toFixed(4)}-${introLin.toFixed(4)})*(t-${duckStart})/${JINGLE_DUCK},` +
      `${bedLin.toFixed(4)}))`;

    const bed =
      `[1:a]aformat=channel_layouts=stereo,aresample=${TARGET_SAMPLE_RATE},` +
      `afade=t=in:st=0:d=${JINGLE_FADE_IN},` +
      `volume=eval=frame:volume='${duckExpr}',` +
      `afade=t=out:st=${fadeOutStart.toFixed(2)}:d=${JINGLE_FADE_OUT}[bed]`;

    // Forsink stemmen så den starter efter musik-introen.
    const delayMs = Math.round(JINGLE_INTRO_SECS * 1000);
    const voice = `[0:a]adelay=${delayMs}:all=1[v]`;

    const filterComplex = `${voice};${bed};[v][bed]amix=inputs=2:duration=first:normalize=0[out]`;
    const ffArgs = [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-i', voicePath,
      '-stream_loop', '-1', '-i', jinglePath,
      '-filter_complex', filterComplex,
      '-map', '[out]',
      '-ar', TARGET_SAMPLE_RATE, '-ac', OUT_CHANNELS,
      '-c:a', 'aac', '-b:a', TARGET_BITRATE, '-movflags', '+faststart',
      outPath,
    ];
    const ff = spawn('ffmpeg', ffArgs, { stdio: 'inherit' });
    ff.on('error', reject);
    ff.on('close', (code) => (code === 0 ? resolvePromise() : reject(new Error(`ffmpeg mix exit ${code}`))));
  });
}

// Producér slutfilen: enten ren stemme, eller stemme + baggrundsjingle.
async function produceFinal(listPath, outPath) {
  if (!JINGLE_PATH) {
    await encodeFromList(listPath, outPath);
    return;
  }
  if (!existsSync(JINGLE_PATH)) {
    throw new Error(`Jingle ikke fundet: ${JINGLE_PATH}`);
  }
  const voiceWav = join(outDir, `${SLUG}.voice.wav`);
  await encodeFromList(listPath, voiceWav, { wav: true });
  const duration = probeDuration(voiceWav);
  console.log(`mixer jingle (${JINGLE_GAIN} dB, loop, fade ${JINGLE_FADE_IN}s/${JINGLE_FADE_OUT}s) under ${duration.toFixed(0)}s stemme...`);
  await mixJingle(voiceWav, JINGLE_PATH, outPath, duration);
  try { rmSync(voiceWav, { force: true }); } catch { /* ignore */ }
}

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / 1024).toFixed(0)} KB`;
}

// ---- Main -----------------------------------------------------------------
async function main() {
  console.log('=== Apropos AI-oplæsning POC ===');
  console.log('slug:', SLUG);
  console.log('model:', MODEL_ID, '| stemme:', VOICE_NAME, '| format:', OUTPUT_FORMAT);

  const outPath = join(outDir, `${SLUG}.m4a`);
  const chunkDir = join(outDir, `${SLUG}.chunks`);
  const listPath = join(chunkDir, 'concat.txt');

  // Hurtig vej: gen-kode kun lyden (fart/EQ) fra cachede chunks uden at kalde ElevenLabs igen.
  if (REENCODE) {
    requireFfmpeg();
    if (!existsSync(listPath)) {
      console.error(`\n--reencode kræver cachede chunks, men ${listPath} findes ikke. Kør uden --reencode først.`);
      process.exit(1);
    }
    console.log(`\nGen-koder fra cache (speed=${SPEED}, treble=${TREBLE_GAIN}dB${JINGLE_PATH ? `, jingle=${JINGLE_GAIN}dB` : ''}) — ingen ElevenLabs-kald...`);
    await produceFinal(listPath, outPath);
    const size = statSync(outPath).size;
    console.log('output m4a:', formatBytes(size));
    console.log('fil:', outPath);
    console.log('\nLyt med:  afplay', JSON.stringify(outPath));
    return;
  }

  console.log('\nHenter artikel fra Webflow...');
  const item = await findArticleBySlug(SLUG);
  if (!item) {
    console.error(`Fandt ingen artikel med slug "${SLUG}".`);
    process.exit(1);
  }
  const fd = item.fieldData || {};
  const title = String(fd.name || '').trim();
  const subtitle = String(fd.subtitle || '').trim();
  const intro = htmlToReadableText(fd.intro || '');
  const bodyText = htmlToReadableText(fd.content || '');
  const authorName = await resolveAuthorName(fd.author);
  const rating = Math.round(Number(fd.stjerne) || 0);

  console.log('titel:', title);
  console.log('forfatter:', authorName || '(ukendt)');
  console.log('stjerner:', rating > 0 ? rating : '(ingen)');

  // Talt intro + outro (brandet)
  const introLine = authorName
    ? `Du lytter til artiklen "${title}", skrevet af ${authorName}, indtalt med kunstig intelligens på vegne af Apropos Magazine.`
    : `Du lytter til artiklen "${title}", indtalt med kunstig intelligens på vegne af Apropos Magazine.`;
  // Stjerne-bedømmelse nævnes efter intro-linjen (kun for anmeldelser med rating).
  const danishNumbers = ['nul', 'en', 'to', 'tre', 'fire', 'fem', 'seks'];
  const ratingLine =
    rating >= 1 && rating <= 6
      ? `Anmeldelsen får ${danishNumbers[rating]} ud af seks stjerner.`
      : '';
  const outroLine = 'Tak fordi du lyttede med på Apropos Magazine.';

  const parts = [introLine, ratingLine, subtitle, intro, bodyText, outroLine].filter(Boolean);
  const fullText = parts.join('\n\n');

  const chunks = chunkText(fullText, MAX_CHARS_PER_CHUNK);
  console.log(`\nTekst: ${fullText.length} tegn → ${chunks.length} chunk(s) (maks ${MAX_CHARS_PER_CHUNK}/chunk)`);

  if (TEXT_ONLY) {
    console.log('\n--- OPLÆSNINGSTEKST (text-only) ---\n');
    console.log(fullText);
    return;
  }

  const apiKey = requireEnv('ELEVENLABS_API_KEY');
  requireFfmpeg();
  rmSync(chunkDir, { recursive: true, force: true });
  mkdirSync(chunkDir, { recursive: true });

  console.log('\nFinder voice_id for', VOICE_NAME, '...');
  const voiceId = await resolveVoiceId(apiKey);
  console.log('voice_id:', voiceId);

  const chunkPaths = [];
  let totalBytes = 0;
  for (let i = 0; i < chunks.length; i++) {
    const chunkPath = join(chunkDir, `chunk-${String(i).padStart(3, '0')}.mp3`);
    process.stdout.write(`  TTS chunk ${i + 1}/${chunks.length} (${chunks[i].length} tegn)... `);
    const bytes = await synthesizeChunk(apiKey, voiceId, chunks[i], chunkPath);
    totalBytes += bytes;
    chunkPaths.push(chunkPath);
    console.log(formatBytes(bytes));
  }

  // Skriv concat-liste og behold chunks som cache til billig --reencode.
  const list = chunkPaths.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join('\n');
  writeFileSync(listPath, list);

  console.log('\nSamler + koder i ét pass med ffmpeg...');
  await produceFinal(listPath, outPath);

  const finalSize = statSync(outPath).size;
  console.log('\n=== Færdig ===');
  console.log(`indstillinger: model=${MODEL_ID}, speed=${SPEED}, treble=${TREBLE_GAIN}dB, ${TARGET_SAMPLE_RATE}Hz`);
  console.log('rå mp3 fra ElevenLabs:', formatBytes(totalBytes));
  console.log('output m4a:', formatBytes(finalSize));
  console.log('chunk-cache (til --reencode):', chunkDir);
  console.log('fil:', outPath);
  console.log('\nLyt med:  afplay', JSON.stringify(outPath));
  console.log('Justér fart/EQ gratis:  node scripts/narration-poc.mjs --reencode --speed=0.88 --treble=-2');
}

main().catch((err) => {
  console.error('\nFejl:', err.message);
  process.exit(1);
});
