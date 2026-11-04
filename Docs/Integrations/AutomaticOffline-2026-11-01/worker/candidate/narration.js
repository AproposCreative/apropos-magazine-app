/**
 * Server-side AI-oplæsning (narration).
 *
 * Genskaber præcis recepten fra scripts/narration-poc.mjs:
 *   stemme "Ellen", model eleven_v3, intro + stjerner + artikel + stjerne-outro + tak,
 *   ffmpeg voice-polish EQ + blød stereobredde, baggrundsjingle med musik-intro,
 *   3s musik-breaker mellem TTS-chunks, bed under oplæsningen og jingle-outro til sidst.
 *
 * Kører i Cloud Functions via ffmpeg-static/ffprobe-static (Linux-binaries hentes
 * ved deploy). Lyd skrives midlertidigt i /tmp og ryddes op bagefter.
 */

const {spawn, execFileSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {randomUUID} = require("node:crypto");
const offlineSource = require("./offlineAudioSource.cjs");
const audioRecipe = require("./narrationAudioRecipe.cjs");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const ffmpegPath = require("ffmpeg-static");
const ffprobePath = require("ffprobe-static").path;

// ---- Config (matcher narration-poc.mjs) -----------------------------------
const BUCKET = "apropos-magazine-6004a.firebasestorage.app";
const NARRATION_PREFIX = "podcasts/narration/";
const ARTICLES_PREFIX = "podcasts/articles/";
const MANIFEST_PATH = "podcasts/manifest.json";
const FEED_PATH = "podcasts/feed.xml";
const SHOW_COVER_URL =
  process.env.PODCAST_SHOW_COVER_URL ||
  "https://ai.aproposmagazine.com/podcast/show-cover.jpg";
const SHOW_TITLE = "Lyt til Apropos Magazine";
const SHOW_DESCRIPTION =
  "Lyt til Apropos Magazines artikler — kultur, film, musik og mere. Hver episode er en artikel fra aproposmagazine.com, oplæst med AI, så du kan følge med på øret, når du ikke har tid til at læse.";
const SHOW_OWNER_EMAIL = "liv@aproposmagazine.com";
const SHOW_OWNER_NAME = "Liv";
const SHOW_LINK = "https://www.aproposmagazine.com";
const RSS_FEED_URL =
  process.env.PODCAST_RSS_FEED_URL ||
  "https://ai.aproposmagazine.com/api/podcast/rss";

const VOICE_NAME = "Ellen";
const MODEL_ID = audioRecipe.MODEL_ID;
const OUTPUT_FORMAT = "mp3_44100_192";
const MAX_CHARS_PER_CHUNK = 2800;
const TARGET_BITRATE = "192k";
const TARGET_SAMPLE_RATE = "44100";
const OUT_CHANNELS = "2";

// Jingle (samme defaults som narration-poc.mjs).
const JINGLE_PATH = path.join(__dirname, "assets", "narration-jingle.wav");
const JINGLE_GAIN = -18; // bed-niveau (dB)
const JINGLE_INTRO_SECS = 6;
const JINGLE_INTRO_GAIN = -5;
const JINGLE_DUCK = 1.5;
const JINGLE_FADE_IN = 1;
const JINGLE_FADE_OUT = 3;
const JINGLE_OUTRO_SECS = 6.5;
const JINGLE_OUTRO_GAIN = -5;
const JINGLE_OUTRO_RISE = 1.2;
// Pause mellem TTS-chunks hvor musikken åbner lidt (radio-breaker).
const CHUNK_BREAKER_SECS = 3;
const JINGLE_BREAKER_GAIN = -12; // lidt over bed (-18)

// Kredit-sikkerhed: stop auto-generering ved dette forbrug af ElevenLabs-kvoten.
const QUOTA_THRESHOLD = 0.80;

// ---- Tekst-helpers (port fra narration-poc.mjs) ---------------------------
function decodeEntities(text) {
  const named = {
    amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ",
    aelig: "æ", AElig: "Æ", oslash: "ø", Oslash: "Ø", aring: "å", Aring: "Å",
    eacute: "é", egrave: "è", uuml: "ü", ouml: "ö", auml: "ä",
    hellip: "…", mdash: "—", ndash: "–", lsquo: "‘", rsquo: "’",
    ldquo: "“", rdquo: "”", laquo: "«", raquo: "»", deg: "°", euro: "€",
  };
  return String(text)
      .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
      .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
      .replace(/&([a-zA-Z]+);/g, (m, name) => (name in named ? named[name] : m));
}

function htmlToReadableText(html) {
  if (!html) return "";
  let text = String(html);
  text = text.replace(/<figcaption[\s\S]*?<\/figcaption>/gi, " ");
  text = text.replace(/<figure[\s\S]*?<\/figure>/gi, " ");
  text = text.replace(/<script[\s\S]*?<\/script>/gi, " ");
  text = text.replace(/<style[\s\S]*?<\/style>/gi, " ");
  text = text.replace(/<iframe[\s\S]*?<\/iframe>/gi, " ");
  text = text.replace(/<\/(p|div|h[1-6]|li|blockquote|tr|section|article)>/gi, "\n\n");
  text = text.replace(/<br\s*\/?>/gi, "\n");
  text = text.replace(/<[^>]+>/g, " ");
  text = decodeEntities(text);
  text = text.replace(/[ \t\u00a0]+/g, " ");
  text = text.replace(/ *\n */g, "\n");
  text = text.replace(/\n{3,}/g, "\n\n");
  return text.trim();
}

function chunkText(text, maxChars) {
  const paragraphs = String(text).split(/\n{2,}/);
  const chunks = [];
  let current = "";
  const pushCurrent = () => {
    if (current.trim()) chunks.push(current.trim());
    current = "";
  };
  for (const para of paragraphs) {
    if ((current + "\n\n" + para).length <= maxChars) {
      current = current ? `${current}\n\n${para}` : para;
      continue;
    }
    pushCurrent();
    if (para.length <= maxChars) {
      current = para;
      continue;
    }
    const sentences = para.match(/[^.!?]+[.!?]+|\S+$/g) || [para];
    for (const sentence of sentences) {
      if ((current + " " + sentence).length <= maxChars) {
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

function titleFromSlug(slug) {
  return String(slug)
      .split("-")
      .filter(Boolean)
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
}

function ratingFromFieldData(fieldData, starsMapping) {
  let rating = Math.round(Number(fieldData.stjerne) || 0);
  if (rating >= 1 && rating <= 6) return rating;
  const label = starsMapping ? starsMapping[String(fieldData.stjerne)] : "";
  const parsed = parseInt(String(label || "").replace(/[^0-9]/g, ""), 10);
  if (parsed >= 1 && parsed <= 6) return parsed;
  return 0;
}

/**
 * Bygger oplæsningsscript:
 *   bodyText   — intro + stjerner (åbning) + artikel (chunkes)
 *   ratingLine — stjerne-opsummering til sidst (eget TTS-kald)
 *   outroLine  — tak for lytning (eget TTS-kald)
 */
function buildNarrationScript(fieldData, authorName, rating) {
  const title = String(fieldData.name || "").trim();
  const subtitle = String(fieldData.subtitle || "").trim();
  const intro = htmlToReadableText(fieldData.intro || "");
  const articleBody = htmlToReadableText(fieldData.content || "");

  const introLine = authorName ?
    `Du lytter til artiklen "${title}", skrevet af ${authorName}, ` +
      "indtalt med kunstig intelligens på vegne af Apropos Magazine." :
    `Du lytter til artiklen "${title}", indtalt med kunstig intelligens ` +
      "på vegne af Apropos Magazine.";

  const danishNumbers = ["nul", "en", "to", "tre", "fire", "fem", "seks"];
  const ratingOpening = rating >= 1 && rating <= 6 ?
    `Anmeldelsen får ${danishNumbers[rating]} ud af seks stjerner.` : "";
  const ratingLine = rating >= 1 && rating <= 6 ?
    `Det blev til ${danishNumbers[rating]} ud af seks stjerner.` : "";
  const outroLine = audioRecipe.OUTRO;

  const bodyText = [introLine, ratingOpening, subtitle, intro, articleBody]
      .filter(Boolean)
      .join("\n\n");
  const fullText = [bodyText, ratingLine, outroLine].filter(Boolean).join("\n\n");
  return {bodyText, ratingLine, outroLine, fullText};
}

// ---- ElevenLabs ------------------------------------------------------------
async function resolveVoiceId(apiKey) {
  const response = await fetch("https://api.elevenlabs.io/v1/voices", {
    headers: {"xi-api-key": apiKey},
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`ElevenLabs /v1/voices ${response.status}: ${body}`);
  }
  const data = await response.json();
  const voices = Array.isArray(data.voices) ? data.voices : [];
  const wanted = VOICE_NAME.trim().toLowerCase();
  const match =
    voices.find((v) => String(v.name || "").trim().toLowerCase() === wanted) ||
    voices.find((v) => String(v.name || "").trim().toLowerCase().startsWith(`${wanted} -`)) ||
    voices.find((v) => String(v.name || "").trim().toLowerCase().split(/\s+/)[0] === wanted);
  if (!match) {
    const names = voices.map((v) => v.name).join(", ");
    throw new Error(`Fandt ikke stemmen "${VOICE_NAME}". Tilgængelige: ${names || "(ingen)"}`);
  }
  return match.voice_id;
}

async function synthesizeChunk(apiKey, voiceId, text, outPath, fullText, {singleAttempt = false} = {}) {
  const body = audioRecipe.speechRequest(text, fullText);
  const url =
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=${OUTPUT_FORMAT}`;
  const maxAttempts = singleAttempt ? 1 : 3;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "Content-Type": "application/json",
          "Accept": "audio/mpeg",
        },
        body: JSON.stringify(body),
      });
      if (!response.ok) {
        const errText = await response.text();
        if (response.status >= 400 && response.status < 500) {
          throw new Error(`ElevenLabs TTS ${response.status}: ${errText}`);
        }
        throw new Error(`ElevenLabs TTS ${response.status}: ${errText} (forsøg ${attempt})`);
      }
      const buffer = Buffer.from(await response.arrayBuffer());
      fs.writeFileSync(outPath, buffer);
      return buffer.length;
    } catch (err) {
      lastError = err;
      if (String(err.message).match(/ TTS 4\d\d:/)) throw err;
      if (attempt < maxAttempts) {
        await new Promise((r) => setTimeout(r, attempt * 2000));
      }
    }
  }
  throw lastError;
}

// Returnerer ElevenLabs-forbrug eller null hvis kaldet fejler.
async function elevenLabsUsage(apiKey) {
  try {
    const response = await fetch("https://api.elevenlabs.io/v1/user/subscription", {
      headers: {"xi-api-key": apiKey},
    });
    if (!response.ok) return null;
    const data = await response.json();
    const count = Number(data.character_count || 0);
    const limit = Number(data.character_limit || 0);
    if (!limit) return null;
    const confirmed = Object.hasOwn(data, "character_count") && Object.hasOwn(data, "character_limit") &&
      typeof data.character_count === "number" && typeof data.character_limit === "number" &&
      Number.isSafeInteger(data.character_count) && data.character_count >= 0 &&
      Number.isSafeInteger(data.character_limit) && data.character_limit > 0 &&
      data.character_count !== null && data.character_limit !== null &&
      Number.isSafeInteger(count) && count >= 0 && Number.isSafeInteger(limit) && limit > 0;
    return {count, limit, ratio: count / limit, confirmed};
  } catch (error) {
    logger.warn("elevenLabsUsage failed:", error.message);
    return null;
  }
}

// ---- ffmpeg ----------------------------------------------------------------
function dbToLinear(db) {
  return Math.pow(10, Number(db) / 20);
}

function voiceFilterChain() {
  // Samme blød EQ + stereobredde som narration-poc.mjs (POLISH + STEREO defaults).
  return [
    "equalizer=f=180:t=q:w=1.0:g=2",
    "equalizer=f=3200:t=q:w=2.0:g=-1.5",
    "equalizer=f=7200:t=q:w=2.5:g=-4",
    "lowpass=f=15000",
    "haas=side_gain=0.3",
  ];
}

function runFfmpeg(args) {
  return new Promise((resolve, reject) => {
    const ff = spawn(ffmpegPath, args, {stdio: ["ignore", "ignore", "pipe"]});
    let stderr = "";
    ff.stderr.on("data", (d) => {
      stderr += d.toString();
    });
    ff.on("error", reject);
    ff.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exit ${code}: ${stderr.slice(-800)}`));
    });
  });
}

function encodeVoiceWav(listPath, outPath) {
  const filters = voiceFilterChain();
  const args = [
    "-hide_banner", "-loglevel", "error", "-y",
    "-f", "concat", "-safe", "0", "-i", listPath,
    "-af", filters.join(","),
    "-ar", TARGET_SAMPLE_RATE, "-ac", OUT_CHANNELS,
    "-c:a", "pcm_s16le", outPath,
  ];
  return runFfmpeg(args);
}

/** Stilhed som MP3 (samme sample rate) til concat mellem TTS-chunks. */
function makeSilenceMp3(outPath, seconds) {
  return runFfmpeg([
    "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", `anullsrc=r=${TARGET_SAMPLE_RATE}:cl=stereo`,
    "-t", String(seconds),
    "-c:a", "libmp3lame", "-b:a", "192k",
    outPath,
  ]);
}

function probeDuration(filePath) {
  const out = execFileSync(ffprobePath, [
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1",
    filePath,
  ]).toString().trim();
  return parseFloat(out) || 0;
}

function escapeConcatPath(p) {
  return p.replace(/'/g, "'\\''");
}

/**
 * Byg concat-liste med stilhed mellem stemme-segmenter, og absolutte
 * breaker-vinduer (inkl. jingle-intro-offset) til musik-bump.
 */
function buildConcatWithBreakers(voicePaths, silencePath, workDir) {
  const lines = [];
  const breakerWindows = [];
  let t = 0;
  for (let i = 0; i < voicePaths.length; i++) {
    const dur = probeDuration(voicePaths[i]);
    lines.push(`file '${escapeConcatPath(voicePaths[i])}'`);
    t += dur;
    if (i < voicePaths.length - 1) {
      breakerWindows.push({
        start: JINGLE_INTRO_SECS + t,
        end: JINGLE_INTRO_SECS + t + CHUNK_BREAKER_SECS,
      });
      lines.push(`file '${escapeConcatPath(silencePath)}'`);
      t += CHUNK_BREAKER_SECS;
    }
  }
  const listPath = path.join(workDir, "concat.txt");
  fs.writeFileSync(listPath, lines.join("\n"));
  return {listPath, breakerWindows, voiceTimelineSecs: t};
}

function bedVolumeWithBreakers(bedLin, breakerLin, windows) {
  let expr = bedLin.toFixed(4);
  for (let i = windows.length - 1; i >= 0; i--) {
    const start = windows[i].start.toFixed(2);
    const end = windows[i].end.toFixed(2);
    expr =
      `if(between(t,${start},${end}),${breakerLin.toFixed(4)},${expr})`;
  }
  return expr;
}

// Musik-intro (højt) → duck til bed → bed/breaker under oplæsning → svulm op til outro.
function mixJingle(voicePath, jinglePath, outPath, voiceDuration, breakerWindows = []) {
  const introLin = dbToLinear(JINGLE_INTRO_GAIN);
  const bedLin = dbToLinear(JINGLE_GAIN);
  const breakerLin = dbToLinear(JINGLE_BREAKER_GAIN);
  const outroLin = dbToLinear(JINGLE_OUTRO_GAIN);
  const duckStart = JINGLE_INTRO_SECS;
  const duckEnd = JINGLE_INTRO_SECS + JINGLE_DUCK;
  const voiceEnd = JINGLE_INTRO_SECS + voiceDuration;
  const riseStart = voiceEnd;
  const riseEnd = voiceEnd + JINGLE_OUTRO_RISE;
  const total = voiceEnd + JINGLE_OUTRO_SECS;
  const fadeOutStart = Math.max(0, total - JINGLE_FADE_OUT);
  const bedExpr = bedVolumeWithBreakers(bedLin, breakerLin, breakerWindows);

  const duckExpr =
    `if(lt(t,${duckStart}),${introLin.toFixed(4)},` +
    `if(lt(t,${duckEnd}),${introLin.toFixed(4)}+(${bedLin.toFixed(4)}-${introLin.toFixed(4)})*(t-${duckStart})/${JINGLE_DUCK},` +
    `if(lt(t,${riseStart.toFixed(2)}),${bedExpr},` +
    `if(lt(t,${riseEnd.toFixed(2)}),${bedLin.toFixed(4)}+(${outroLin.toFixed(4)}-${bedLin.toFixed(4)})*(t-${riseStart.toFixed(2)})/${JINGLE_OUTRO_RISE},` +
    `${outroLin.toFixed(4)}))))`;

  const bed =
    `[1:a]aformat=channel_layouts=stereo,aresample=${TARGET_SAMPLE_RATE},` +
    `afade=t=in:st=0:d=${JINGLE_FADE_IN},` +
    `volume=eval=frame:volume='${duckExpr}',` +
    `afade=t=out:st=${fadeOutStart.toFixed(2)}:d=${JINGLE_FADE_OUT}[bed]`;

  const delayMs = Math.round(JINGLE_INTRO_SECS * 1000);
  const voice = `[0:a]adelay=${delayMs}:all=1,apad=whole_dur=${total.toFixed(2)}[v]`;

  const filterComplex = `${voice};${bed};[v][bed]amix=inputs=2:duration=first:normalize=0[out]`;
  const args = [
    "-hide_banner", "-loglevel", "error", "-y",
    "-i", voicePath,
    "-stream_loop", "-1", "-i", jinglePath,
    "-filter_complex", filterComplex,
    "-map", "[out]",
    "-ar", TARGET_SAMPLE_RATE, "-ac", OUT_CHANNELS,
    "-c:a", "aac", "-b:a", TARGET_BITRATE, "-movflags", "+faststart",
    outPath,
  ];
  return runFfmpeg(args);
}

async function produceFinal(listPath, outPath, workDir, jingleVersion) {
  const voiceWav = path.join(workDir, "voice.wav");
  await encodeVoiceWav(listPath, voiceWav);
  const duration = probeDuration(voiceWav);
  logger.info(`narration mix: ${audioRecipe.RECIPE_VERSION}/${jingleVersion}, no inserted pauses, tale ${duration.toFixed(0)}s`);
  await runFfmpeg(audioRecipe.mixArgs(__dirname, jingleVersion, voiceWav, outPath, duration));
  try {
    fs.rmSync(voiceWav, {force: true});
  } catch (e) { /* ignore */ }
}

// ---- Storage / Firestore ---------------------------------------------------
function publicURL(storagePath, token) {
  const encoded = encodeURIComponent(storagePath);
  let url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media`;
  if (token) url += `&token=${token}`;
  return url;
}

function extractToken(metadata) {
  const raw = metadata && metadata.metadata &&
    metadata.metadata.firebaseStorageDownloadTokens;
  if (!raw) return null;
  return String(raw).split(",")[0].trim() || null;
}

async function resolveDownloadToken(bucket, storagePath) {
  try {
    const [metadata] = await bucket.file(storagePath).getMetadata();
    const existing = extractToken(metadata);
    if (existing) return existing;
  } catch (error) {
    if (error && error.code !== 404) {
      logger.warn(`token read ${storagePath}: ${error.message}`);
    }
  }
  return randomUUID();
}

function slugToId(slug) {
  const compact = String(slug)
      .replace(/[^a-z0-9]+/gi, "-")
      .replace(/^-|-$/g, "")
      .toLowerCase();
  return compact || slug;
}

function isAudioFile(name) {
  return /\.(m4a|mp3|aac|wav|mp4)$/i.test(name);
}

async function listAudioObjects(bucket, prefix) {
  const [files] = await bucket.getFiles({prefix});
  return files.filter((f) => isAudioFile(f.name) && !f.name.endsWith("/"));
}

function catalogObjectPath(value) {
  try {
    const url = new URL(value);
    const prefix = `/v0/b/${BUCKET}/o/`;
    return url.protocol === "https:" && url.hostname === "firebasestorage.googleapis.com" && url.pathname.startsWith(prefix)
      ? decodeURIComponent(url.pathname.slice(prefix.length)) : null;
  } catch { return null; }
}
function hasSourceTuple(row) {
  return /^[a-f\d]{24}$/.test(row?.articleId || "") && /^cms-sha256-v1:[a-f\d]{64}$/.test(row?.sourceContentRevision || "");
}
async function articleHasAudio(bucket, slug) {
  const bound = [];
  for (const prefix of [ARTICLES_PREFIX, NARRATION_PREFIX]) {
    try {
      const [files] = await bucket.getFiles({prefix: `${prefix}${slug}/`});
      for (const file of files.filter(f => isAudioFile(f.name))) {
        if (!offlineSource.isBoundPath(file.name)) return "exists";
        bound.push(file);
      }
    } catch { return "unresolved_audio"; }
  }
  if (!bound.length) return null;
  // An orphan, even a complete one, is not a committed publication receipt.
  try {
    const [bytes] = await bucket.file(MANIFEST_PATH).download();
    const manifest = JSON.parse(bytes.toString("utf8"));
    if (!Array.isArray(manifest.episodes)) return "unresolved_audio";
    for (const file of bound) {
      const refs = manifest.episodes.filter(x => catalogObjectPath(x.audioURL) === file.name);
      if (refs.length !== 1 || !hasSourceTuple(refs[0])) continue;
      const [metadata] = await file.getMetadata();
      const [sidecar] = await bucket.file(`${file.name}.json`).download();
      const proof = offlineSource.objectBinding(file.name, metadata, JSON.parse(sidecar.toString("utf8")));
      const current = offlineSource.captureSource(await loadArticle(admin.firestore(), proof.articleId, slug), proof.articleId, slug);
      if (refs[0].articleId === proof.articleId && refs[0].sourceContentRevision === proof.sourceContentRevision && offlineSource.sameSource(proof, current)) return "exists";
    }
  } catch { /* Ambiguous/unknown outcomes remain explicit, never paid retries. */ }
  return "unresolved_audio";
}

async function uploadObject(bucket, localPath, storagePath, token, sourceBinding) {
  await bucket.upload(localPath, {
    destination: storagePath,
    metadata: {
      contentType: "audio/mp4",
      cacheControl: "public, max-age=31536000, immutable",
      metadata: {
        firebaseStorageDownloadTokens: token,
        podcastOptimized: "true",
        ...(sourceBinding ? {offlineAudioBinding: JSON.stringify(sourceBinding)} : {}),
      },
    },
    resumable: true,
    preconditionOpts: {ifGenerationMatch: 0},
  });
}

function plainSnippet(text, maxLen = 4000) {
  const cleaned = htmlToReadableText(text || "").replace(/\s+/g, " ").trim();
  if (!cleaned) return "";
  return cleaned.length > maxLen ? `${cleaned.slice(0, maxLen - 1).trim()}…` : cleaned;
}

function descriptionFromFieldData(fieldData) {
  for (const key of ["summary", "excerpt", "meta-description", "intro", "subtitle", "content"]) {
    const snippet = plainSnippet(fieldData?.[key]);
    if (snippet) return snippet;
  }
  return "";
}

function coverUrlFromFieldData(fieldData) {
  for (const key of ["cover", "thumbnail", "main-image", "image"]) {
    const v = fieldData?.[key];
    if (typeof v === "string" && /^https?:\/\//i.test(v.trim())) return v.trim();
    if (v && typeof v === "object" && typeof v.url === "string" && /^https?:\/\//i.test(v.url)) {
      return v.url.trim();
    }
  }
  return "";
}

function formatItunesDuration(totalSeconds) {
  const s = Math.max(0, Math.floor(totalSeconds || 0));
  const hours = Math.floor(s / 3600);
  const minutes = Math.floor((s % 3600) / 60);
  const seconds = s % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function escapeXml(value) {
  return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
}

function cdata(value) {
  return `<![CDATA[${String(value || "").replace(/]]>/g, "]]]]><![CDATA[>")}]]>`;
}

function buildRssXml(episodes) {
  const items = episodes.map((ep) => {
    const link = `https://www.aproposmagazine.com/articles/${ep.articleSlug}`;
    const guid = ep.guid || ep.id || ep.articleSlug;
    const image = ep.imageURL || SHOW_COVER_URL;
    const author = (ep.hosts || []).join(", ") || SHOW_TITLE;
    const description = ep.description ||
      `${ep.title}. Lyt til artiklen — Apropos Magazine.`;
    const length = ep.audioBytes > 0 ? String(ep.audioBytes) : "0";
    const duration = ep.durationSeconds > 0 ?
      formatItunesDuration(ep.durationSeconds) : null;
    const lines = [
      "    <item>",
      `      <title>${escapeXml(ep.title)}</title>`,
      `      <description>${cdata(description)}</description>`,
      `      <link>${escapeXml(link)}</link>`,
      `      <guid isPermaLink="false">${escapeXml(guid)}</guid>`,
      `      <pubDate>${new Date(ep.publishedAt).toUTCString()}</pubDate>`,
      `      <enclosure url="${escapeXml(ep.audioURL)}" length="${length}" type="audio/mp4" />`,
      `      <itunes:author>${escapeXml(author)}</itunes:author>`,
      `      <itunes:summary>${cdata(description)}</itunes:summary>`,
      `      <itunes:explicit>false</itunes:explicit>`,
      `      <itunes:image href="${escapeXml(image)}" />`,
      "      <itunes:episodeType>full</itunes:episodeType>",
    ];
    if (duration) lines.push(`      <itunes:duration>${duration}</itunes:duration>`);
    lines.push("    </item>");
    return lines.join("\n");
  }).join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
  xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${escapeXml(SHOW_TITLE)}</title>
    <link>${escapeXml(SHOW_LINK)}</link>
    <description>${cdata(SHOW_DESCRIPTION)}</description>
    <language>da-dk</language>
    <atom:link href="${escapeXml(RSS_FEED_URL)}" rel="self" type="application/rss+xml" />
    <itunes:author>${escapeXml(SHOW_TITLE)}</itunes:author>
    <itunes:summary>${cdata(SHOW_DESCRIPTION)}</itunes:summary>
    <itunes:type>episodic</itunes:type>
    <itunes:owner>
      <itunes:name>${escapeXml(SHOW_OWNER_NAME)}</itunes:name>
      <itunes:email>${escapeXml(SHOW_OWNER_EMAIL)}</itunes:email>
    </itunes:owner>
    <itunes:explicit>false</itunes:explicit>
    <itunes:category text="Arts" />
    <itunes:image href="${escapeXml(SHOW_COVER_URL)}" />
    <image>
      <url>${escapeXml(SHOW_COVER_URL)}</url>
      <title>${escapeXml(SHOW_TITLE)}</title>
      <link>${escapeXml(SHOW_LINK)}</link>
    </image>
${items}
  </channel>
</rss>
`;
}

async function writeFeedMirror(bucket, episodes) {
  let token = null;
  try {
    const [existing] = await bucket.file(FEED_PATH).getMetadata();
    token = extractToken(existing);
  } catch (e) {
    token = null;
  }
  if (!token) token = randomUUID();
  await bucket.file(FEED_PATH).save(buildRssXml(episodes), {
    resumable: false,
    metadata: {
      contentType: "application/rss+xml; charset=utf-8",
      cacheControl: "public, max-age=300",
      metadata: {firebaseStorageDownloadTokens: token},
    },
  });
}

async function writeNarrationMetadata(bucket, slug, metadata, sourceBinding, objectGeneration) {
  const metadataPath = sourceBinding ? `${sourceBinding.objectPath}.json` : `${NARRATION_PREFIX}${slug}/narration.json`;
  const payload = {
    title: metadata.title,
    hosts: metadata.hosts,
    kind: "ai",
    ...(sourceBinding ? {sourceBinding, objectGeneration: String(objectGeneration)} : {}),
    updatedAt: new Date().toISOString(),
  };
  if (metadata.durationSeconds > 0) payload.durationSeconds = Math.round(metadata.durationSeconds);
  if (metadata.audioBytes > 0) payload.audioBytes = Math.round(metadata.audioBytes);
  if (metadata.description) payload.description = String(metadata.description).slice(0, 4000);
  if (metadata.imageURL) payload.imageURL = String(metadata.imageURL);
  if (metadata.audioRecipe) payload.audioRecipe = metadata.audioRecipe;
  await bucket.file(metadataPath).save(JSON.stringify(payload, null, 2), {
    ...(sourceBinding ? {preconditionOpts: {ifGenerationMatch: 0}} : {}),
    contentType: "application/json",
    resumable: false,
  });
}

async function readJsonMetadata(bucket, metadataPath) {
  try {
    const [buffer] = await bucket.file(metadataPath).download();
    const parsed = JSON.parse(buffer.toString("utf8"));
    return {
      title: String(parsed.title || "").trim(),
      hosts: Array.isArray(parsed.hosts) ? parsed.hosts.map(String) : [],
      durationSeconds: Number(parsed.durationSeconds) || 0,
      audioBytes: Number(parsed.audioBytes) || 0,
      description: String(parsed.description || "").trim(),
      imageURL: String(parsed.imageURL || "").trim(),
    };
  } catch (e) {
    return {
      title: "",
      hosts: [],
      durationSeconds: 0,
      audioBytes: 0,
      description: "",
      imageURL: "",
    };
  }
}

// Regenererer podcasts/manifest.json (port af syncManifest fra podcast-auto-publish.mjs).
async function syncManifest(bucket, {assertCurrent = async () => {}, targetBinding = null, authorizedBinding = null, repair = null} = {}) {
  await assertCurrent();
  // Snapshot/CAS protects unrelated entries from concurrent catalog writers.
  const [priorMetadata] = await bucket.file(MANIFEST_PATH).getMetadata();
  if (priorMetadata.contentEncoding !== undefined && priorMetadata.contentEncoding !== "identity") throw new Error("Unsupported catalog content encoding");
  const [priorBytes] = await bucket.file(MANIFEST_PATH).download();
  const priorManifest = JSON.parse(priorBytes.toString("utf8"));
  if (!/^[1-9]\d*$/.test(String(priorMetadata.metageneration || "")) || priorMetadata.retention ||
      priorMetadata.retentionExpirationTime || priorMetadata.temporaryHold === true || priorMetadata.eventBasedHold === true) {
    throw new Error("Unsupported catalog metadata policy");
  }
  // Preserve known writable headers and the complete SDK custommetadata map.
  // Read-only generation/hash/time fields are not submitted; ACL is untouched.
  const catalogMetadata = {};
  for (const key of ["cacheControl", "contentDisposition", "contentEncoding", "contentLanguage", "contentType", "customTime", "temporaryHold", "eventBasedHold"]) {
    if (priorMetadata[key] !== undefined) catalogMetadata[key] = priorMetadata[key];
  }
  catalogMetadata.metadata = {...(priorMetadata.metadata || {})};
  if (!Array.isArray(priorManifest.episodes) || !/^\d+$/.test(String(priorMetadata.generation || ""))) throw new Error("Invalid source catalog snapshot");
  const episodes = [];
  if (targetBinding) {
    const targetID = `ai-${slugToId(targetBinding.articleSlug)}`;
    const targets = priorManifest.episodes.filter(x => x.id === targetID);
    if (targets.length !== 1 || !repair) throw new Error("Exact repair catalog target required");
    const [oldMetadata] = await bucket.file(repair.oldObjectPath).getMetadata();
    offlineSource.validateRepair(repair, targetBinding, oldMetadata);
    if (targets[0].audioURL !== publicURL(repair.oldObjectPath, extractToken(oldMetadata))) throw new Error("Repair catalog target changed");
    const [metadata] = await bucket.file(targetBinding.objectPath).getMetadata();
    const [bytes] = await bucket.file(`${targetBinding.objectPath}.json`).download();
    const sidecar = JSON.parse(bytes.toString("utf8"));
    const proof = offlineSource.objectBinding(targetBinding.objectPath, metadata, sidecar);
    if (offlineSource.canonicalJSON(proof) !== offlineSource.canonicalJSON(targetBinding)) throw new Error("Repair object proof changed");
    const token = extractToken(metadata);if (!token) throw new Error("Repair object token unavailable");
    const target = {...targets[0], articleId: proof.articleId, sourceContentRevision: proof.sourceContentRevision,
      audioURL: publicURL(proof.objectPath, token), audioBytes: proof.audioBytes};
    if (sidecar.durationSeconds > 0) target.durationSeconds = Math.round(sidecar.durationSeconds);
    episodes.push(...priorManifest.episodes.map(x => x.id === targetID ? target : x));
  } else {
  const humanSlugs = new Set();

  const humanFiles = await listAudioObjects(bucket, ARTICLES_PREFIX);
  for (const file of humanFiles) {
    const parts = file.name.split("/").filter(Boolean);
    const slug = parts[parts.length - 2];
    if (!slug) continue;
    const [metadata] = await file.getMetadata();
    const token = extractToken(metadata);
    const priorRows = priorManifest.episodes.filter(x => x.id === slugToId(slug));
    const previouslyBound = priorRows.filter(x => Object.hasOwn(x, "articleId") || Object.hasOwn(x, "sourceContentRevision"));
    if (previouslyBound.length) {
      const prior = previouslyBound[0], observedTime = metadata.updated || metadata.timeCreated;
      if (priorRows.length !== 1 || previouslyBound.length !== 1 || !hasSourceTuple(prior) || prior.kind !== "human" ||
          !token || prior.audioURL !== publicURL(file.name, token) || prior.articleSlug !== slug ||
          !Number.isSafeInteger(prior.audioBytes) || prior.audioBytes <= 0 || prior.audioBytes !== Number(metadata.size) ||
          typeof prior.publishedAt !== "string" || !Number.isFinite(Date.parse(prior.publishedAt)) ||
          typeof observedTime !== "string" || Date.parse(prior.publishedAt) !== Date.parse(observedTime) ||
          !/^[1-9]\d*$/.test(String(metadata.generation || "")) ||
          (prior.audioObjectGeneration !== undefined && prior.audioObjectGeneration !== String(metadata.generation)) ||
          (prior.audioSHA256 !== undefined && (!/^[a-f\d]{64}$/.test(prior.audioSHA256) || prior.audioSHA256 !== metadata.metadata?.audioSHA256))) {
        throw new Error("Existing human source proof no longer matches recording");
      }
      humanSlugs.add(slug);episodes.push(prior);continue;
    }
    if (!token) continue;
    const meta = await readJsonMetadata(bucket, `${ARTICLES_PREFIX}${slug}/podcast.json`);
    humanSlugs.add(slug);
    const size = Number(metadata.size) || meta.audioBytes || 0;
    const episode = {
      id: slugToId(slug),
      articleSlug: slug,
      title: meta.title || titleFromSlug(slug),
      subtitle: "Lyt til artiklen",
      audioURL: publicURL(file.name, token),
      hosts: meta.hosts.length ? meta.hosts : ["Apropos Magazine"],
      publishedAt: metadata.updated || metadata.timeCreated || new Date().toISOString(),
      guid: slugToId(slug),
      kind: "human",
      imageURL: meta.imageURL || SHOW_COVER_URL,
    };
    if (meta.durationSeconds > 0) episode.durationSeconds = Math.round(meta.durationSeconds);
    if (size > 0) episode.audioBytes = Math.round(size);
    if (meta.description) episode.description = meta.description;
    episodes.push(episode);
  }

  const narrationFiles = await listAudioObjects(bucket, NARRATION_PREFIX);
  const selectedNarrations = [];
  const groups = new Map();
  for (const file of narrationFiles) {
    const slug = file.name.split("/").filter(Boolean).at(-2);
    if (!slug || humanSlugs.has(slug)) continue;
    if (!groups.has(slug)) groups.set(slug, []);
    groups.get(slug).push(file);
  }
  const acceptedBindings = new Map();
  for (const [slug, files] of groups) {
    const bound = [], legacy = [];
    for (const file of files) {
      const references = priorManifest.episodes.filter(x => catalogObjectPath(x.audioURL) === file.name);
      const authorized = authorizedBinding?.objectPath === file.name;
      if (offlineSource.isBoundPath(file.name) && !authorized && !references.length) continue;
      const [metadata] = await file.getMetadata();
      if (!offlineSource.isBoundPath(file.name) && !metadata.metadata?.offlineAudioBinding) { legacy.push(file); continue; }
      if (!authorized && !references.length) continue;
      const [bytes] = await bucket.file(`${file.name}.json`).download();
      const sidecar = JSON.parse(bytes.toString("utf8"));
      const binding = offlineSource.objectBinding(file.name, metadata, sidecar);
      if (authorized && offlineSource.canonicalJSON(authorizedBinding) !== offlineSource.canonicalJSON(binding)) throw new Error("Authorized source proof changed");
      if (references.length && (references.length !== 1 || references[0].kind !== "ai" || !hasSourceTuple(references[0]) ||
          references[0].articleId !== binding.articleId || references[0].sourceContentRevision !== binding.sourceContentRevision)) throw new Error("Referenced source proof changed");
      const article = await loadArticle(admin.firestore(), binding.articleId, slug);
      const current = offlineSource.captureSource(article, binding.articleId, slug);
      if (!offlineSource.sameSource(binding, current)) continue;
      bound.push({file, binding, sidecar, token: extractToken(metadata)});
    }
    const target = authorizedBinding && bound.find(x => x.binding.objectPath === authorizedBinding.objectPath);
    // No clock-based choice between different renders of the same source.
    const prior = priorManifest.episodes.find(x => x.id === `ai-${slugToId(slug)}`);
    const retained = prior && bound.find(x => x.token && prior.audioURL === publicURL(x.file.name, x.token));
    const choice = target || retained || (bound.length === 1 ? bound[0] : null);
    if (bound.length > 1 && !choice) throw new Error("Ambiguous source-bound narration");
    if (choice) { selectedNarrations.push(choice.file); acceptedBindings.set(choice.file.name, choice); }
    else if (legacy.length === 1) selectedNarrations.push(legacy[0]);
    else if (legacy.length > 1) throw new Error("Ambiguous legacy narration");
  }
  if (authorizedBinding && !acceptedBindings.has(authorizedBinding.objectPath)) throw new Error("Authorized source proof unavailable");
  for (const file of selectedNarrations) {
    const parts = file.name.split("/").filter(Boolean);
    const slug = parts[parts.length - 2];
    if (!slug || humanSlugs.has(slug)) continue;
    const [metadata] = await file.getMetadata();
    const token = extractToken(metadata);
    if (!token) continue;
    const accepted = acceptedBindings.get(file.name);
    const meta = accepted ? accepted.sidecar : await readJsonMetadata(bucket, `${NARRATION_PREFIX}${slug}/narration.json`);
    const size = Number(metadata.size) || meta.audioBytes || 0;
    const episode = {
      id: `ai-${slugToId(slug)}`,
      ...(accepted ? {articleId: accepted.binding.articleId, sourceContentRevision: accepted.binding.sourceContentRevision} : {}),
      articleSlug: slug,
      title: meta.title || titleFromSlug(slug),
      subtitle: "Lyt til artiklen",
      audioURL: publicURL(file.name, token),
      hosts: meta.hosts.length ? meta.hosts : ["Apropos Magazine"],
      publishedAt: metadata.updated || metadata.timeCreated || new Date().toISOString(),
      kind: "ai",
      guid: `ai-${slugToId(slug)}`,
      imageURL: meta.imageURL || SHOW_COVER_URL,
    };
    if (meta.durationSeconds > 0) episode.durationSeconds = Math.round(meta.durationSeconds);
    if (size > 0) episode.audioBytes = Math.round(size);
    if (meta.description) episode.description = meta.description;
    episodes.push(episode);
  }

    // Preserve unrelated legacy entries exactly, including extension metadata.
    for (let i = 0; i < episodes.length; i++) {
      const prior = priorManifest.episodes.find(x => x.id === episodes[i].id);
      if (prior && !prior.sourceContentRevision && !episodes[i].sourceContentRevision) episodes[i] = prior;
    }
    episodes.sort((a, b) => new Date(b.publishedAt) - new Date(a.publishedAt));
  }

  // RSS should not include English CMS translations (app may still list them in manifest).
  const rssEpisodes = episodes.filter((ep) => {
    const slug = String(ep.articleSlug || "").toLowerCase();
    if (slug.endsWith("-en") || slug.includes("-en-")) return false;
    // EN translation slugs (do not treat "oe"/"aa" as Danish — "oehavet" is øhavet).
    if (/-(community|maritime|folk-high-school|vibes?)(-|$)/.test(slug)) {
      return false;
    }
    if (/-(and|with|for)-/.test(slug)) return false;
    return true;
  });

  if (!extractToken(priorMetadata)) catalogMetadata.metadata.firebaseStorageDownloadTokens = randomUUID();
  await assertCurrent();
  const manifest = {...priorManifest, updatedAt: new Date().toISOString(), episodes};
  await bucket.file(MANIFEST_PATH).save(JSON.stringify(manifest, null, 2), {
    resumable: false,
    preconditionOpts: {ifGenerationMatch: String(priorMetadata.generation), ifMetagenerationMatch: String(priorMetadata.metageneration)},
    metadata: catalogMetadata,
  });
  await assertCurrent();
  // Maintenance repairs replace app-only offline access, never reannounce RSS.
  if (!targetBinding) {
    try {
      await writeFeedMirror(bucket, rssEpisodes);
    } catch (e) {
      logger.warn(`narration feed mirror failed: ${e.message}`);
    }
  }
  logger.info(
      `narration manifest synced (${episodes.length} episodes, ` +
      `${targetBinding ? "RSS unchanged" : `${rssEpisodes.length} in RSS`})`,
  );
}

async function loadArticle(db, articleId, slug) {
  if (articleId) {
    const doc = await db.collection("articles").doc(String(articleId)).get();
    if (doc.exists) return doc.data();
    return null;
  }
  const query = await db.collection("articles")
      .where("fieldData.slug", "==", slug)
      .limit(1)
      .get();
  if (!query.empty) return query.docs[0].data();
  return null;
}

async function resolveAuthorName(db, authorId) {
  if (!authorId) return "";
  try {
    const doc = await db.collection("authors").doc(String(authorId)).get();
    if (doc.exists) {
      return String((doc.data().fieldData || {}).name || "").trim();
    }
  } catch (e) { /* ignore */ }
  return "";
}

async function loadStarsMapping(db) {
  try {
    const doc = await db.collection("metadata").doc("starsMapping").get();
    if (doc.exists) return doc.data().mapping || {};
  } catch (e) { /* ignore */ }
  return {};
}

async function recordAdminAlert(db, type, details) {
  try {
    await db.collection("admin_alerts").add({
      type,
      ...details,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.warn("recordAdminAlert failed:", e.message);
  }
}

/**
 * Hovedfunktion: generér og udgiv en AI-oplæsning for én artikel.
 * Returnerer et statusobjekt; kaster kun ved uventede fejl.
 */
async function readBoundedSidecar(bucket, name) {
  const [before] = await bucket.file(name).getMetadata();
  if (!/^[1-9]\d*$/.test(String(before.generation)) || !/^[1-9]\d*$/.test(String(before.metageneration)) ||
      !Number.isSafeInteger(Number(before.size)) || Number(before.size) < 1 || Number(before.size) > 1024 * 1024) throw new Error("Invalid bounded sidecar");
  const [bytes] = await bucket.file(name, {generation: String(before.generation)}).download();
  const [after] = await bucket.file(name).getMetadata();
  if (bytes.length !== Number(before.size) || JSON.stringify(before) !== JSON.stringify(after)) throw new Error("Sidecar changed during read");
  return JSON.parse(bytes.toString("utf8"));
}
async function generateAndPublishNarration({slug, articleId, name, apiKey, repair, oldSource, renderBudget, publishMaintenance, registerImmutableOutput, assertCurrent: assertJobCurrent = async () => {}}) {
  const db = admin.firestore();
  const bucket = admin.storage().bucket(BUCKET);

  const existingAudio = !repair && !publishMaintenance ? await articleHasAudio(bucket, slug) : null;
  if (existingAudio) {
    logger.info(`narration: ${slug} existing audio state ${existingAudio} — skipping`);
    return {status: existingAudio};
  }
  if (!/^[a-f\d]{24}$/.test(articleId || "")) throw new Error("Canonical narration source ID required");

  const article = await loadArticle(db, articleId, slug);
  if (!article || !article.fieldData) {
    logger.warn(`narration: ingen artikel fundet for ${slug} (${articleId})`);
    return {status: "no_article"};
  }
  const source = offlineSource.captureSource(article, articleId, slug);
  const immutableArticle = JSON.parse(JSON.stringify(article));
  const assertCurrent = async () => {
    if (assertJobCurrent) await assertJobCurrent();
    const latest = await loadArticle(db, source.articleId, slug);
    if (!offlineSource.sameSource(source, offlineSource.captureSource(latest, source.articleId, slug))) throw new Error("Narration source changed");
    if (assertJobCurrent) await assertJobCurrent();
    if (repair) {
      const [oldMetadata] = await bucket.file(repair.oldObjectPath).getMetadata();
      const oldSidecar = oldSource ? await readBoundedSidecar(bucket, `${repair.oldObjectPath}.json`) : null;
      offlineSource.validateMaintenanceRepair(repair, source, oldMetadata, oldSource, oldSidecar);
    }
  };
  if (repair) {
    const [oldMetadata] = await bucket.file(repair.oldObjectPath).getMetadata();
    const oldSidecar = oldSource ? await readBoundedSidecar(bucket, `${repair.oldObjectPath}.json`) : null;
      offlineSource.validateMaintenanceRepair(repair, source, oldMetadata, oldSource, oldSidecar);
  }
  await assertCurrent();
  const fieldData = immutableArticle.fieldData;

  const authorName = await resolveAuthorName(db, fieldData.author);
  const starsMapping = await loadStarsMapping(db);
  const rating = ratingFromFieldData(fieldData, starsMapping);
  const script = buildNarrationScript(fieldData, authorName, rating);
  const {bodyText, ratingLine, outroLine, fullText} = script;

  if (fullText.length < 50) {
    logger.warn(`narration: ${slug} har for lidt tekst (${fullText.length} tegn)`);
    return {status: "empty"};
  }

  // Compare this worker's OWN actual recipe before any provider/usage call.
  if (publishMaintenance) offlineSource.validateRenderBudget(fullText, renderBudget);

  // Resolve once per episode, validate retained assets before any paid synthesis.
  const jingleSelection = await audioRecipe.readJingleSelection(db, process.env.NARRATION_JINGLE_VERSION);
  const jingleVersion = jingleSelection.version;
  audioRecipe.verifyAssets(__dirname, jingleVersion);

  // Kredit-cap: stop før ElevenLabs-kvoten brændes.
  await assertCurrent();
  const usage = await elevenLabsUsage(apiKey);
  await assertCurrent();
  if (publishMaintenance && (!usage || usage.confirmed !== true || !Number.isSafeInteger(usage.count) || usage.count < 0 ||
      !Number.isSafeInteger(usage.limit) || usage.limit <= 0 || !Number.isFinite(usage.ratio))) {
    throw new Error("Provider quota could not be confirmed before maintenance");
  }
  if (usage) {
    const projected = usage.count + fullText.length;
    if (usage.ratio >= QUOTA_THRESHOLD || projected > usage.limit) {
      logger.error(
          `narration: kvote-grænse nået (${Math.round(usage.ratio * 100)}% brugt, ` +
          `${usage.count}/${usage.limit}) — springer ${slug} over`,
      );
      await recordAdminAlert(db, "elevenlabs_quota", {
        slug,
        name: name || "",
        characterCount: usage.count,
        characterLimit: usage.limit,
        usedPercent: Math.round(usage.ratio * 100),
        projectedChars: fullText.length,
        message:
          `AI-oplæsning af "${name || slug}" sprunget over: ElevenLabs-kvote ` +
          `${Math.round(usage.ratio * 100)}% brugt. Generér manuelt senere ` +
          "med scripts/narration-queue.mjs, eller vent til kvoten nulstilles.",
      });
      return {status: "deferred_quota", usage};
    }
  }

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), `narr-${slugToId(slug)}-`));
  try {
    const voiceId = await resolveVoiceId(apiKey);
    await assertCurrent();
    const speechChunks = audioRecipe.narrationChunks(script, MAX_CHARS_PER_CHUNK);
    logger.info(`narration: ${slug} — ${fullText.length} tegn → ${speechChunks.length} sammenhængende chunk(s), ${audioRecipe.RECIPE_VERSION}/${jingleVersion}`);
    const voicePaths = [];
    for (let i = 0; i < speechChunks.length; i++) {
      const chunkPath = path.join(workDir, `chunk-${String(i).padStart(3, "0")}.mp3`);
      await assertCurrent();
      await synthesizeChunk(apiKey, voiceId, speechChunks[i], chunkPath, fullText, {singleAttempt: Boolean(publishMaintenance)});
      await assertCurrent();
      voicePaths.push(chunkPath);
    }
    const listPath = path.join(workDir, "concat.txt");
    fs.writeFileSync(listPath, voicePaths.map(p => `file '${escapeConcatPath(p)}'`).join("\n"));

    const outPath = path.join(workDir, `${slugToId(slug)}.m4a`);
    await produceFinal(listPath, outPath, workDir, jingleVersion);
    await assertCurrent();

    const durationSeconds = Math.round(probeDuration(outPath) || 0);
    const audioBytes = fs.statSync(outPath).size;
    const description = descriptionFromFieldData(fieldData);
    const imageURL = coverUrlFromFieldData(fieldData) || SHOW_COVER_URL;

    const renderStat = fs.lstatSync(outPath);
    if (!renderStat.isFile() || !Number.isSafeInteger(renderStat.size) || renderStat.size <= 0 || renderStat.size > 256 * 1024 * 1024) throw new Error("Invalid rendered audio size");
    const binding = offlineSource.makeBinding(source, fs.readFileSync(outPath));
    offlineSource.validateBinding(binding, binding.objectPath);
    if (registerImmutableOutput) await registerImmutableOutput(binding);
    const destPath = binding.objectPath;
    const token = await resolveDownloadToken(bucket, destPath);
    await assertCurrent();
    await uploadObject(bucket, outPath, destPath, token, binding);
    const [uploaded] = await bucket.file(destPath).getMetadata();
    if (String(uploaded.size) !== String(binding.audioBytes) || uploaded.metadata?.offlineAudioBinding !== JSON.stringify(binding)) throw new Error("Uploaded source proof mismatch");
    await assertCurrent();

    const title = String(fieldData.name || "").trim() || titleFromSlug(slug);
    const hosts = authorName ? [authorName] : ["Apropos Magazine"];
    await writeNarrationMetadata(bucket, slug, {
      title,
      hosts,
      durationSeconds,
      audioBytes,
      description,
      imageURL,
      audioRecipe: {version: audioRecipe.RECIPE_VERSION, jingleVersion, selectionRevision: jingleSelection.revision, voiceId, modelId: MODEL_ID, stability: 1, insertedPauseSeconds: 0, outroCopy: "free-ad-free-v1"},
    }, binding, uploaded.generation);

    await assertCurrent();
    if (publishMaintenance) {
      await publishMaintenance({binding, audioURL: publicURL(destPath, token), episode: {
        id: `ai-${slugToId(slug)}`, ...(!repair ? {guid: `ai-${slugToId(slug)}`} : {}), articleSlug: slug,
        title, subtitle: "Lyt til artiklen", hosts, kind: "ai", imageURL,
        publishedAt: immutableArticle.lastPublished, durationSeconds, description,
      }});
    } else {
      await syncManifest(bucket, {assertCurrent, targetBinding: repair ? binding : null, authorizedBinding: repair ? null : binding, repair});
    }

    logger.info(`narration: udgivet ${slug} → ${publicURL(destPath, token)}`);
    return {status: "published", title};
  } finally {
    try {
      fs.rmSync(workDir, {recursive: true, force: true});
    } catch (e) { /* ignore */ }
  }
}

async function readNarrationScript({slug, articleId}) {
  const db = admin.firestore();
  const article = await loadArticle(db, articleId, slug);
  const source = offlineSource.captureSource(article, articleId, slug);
  const authorName = await resolveAuthorName(db, article.fieldData.author);
  const starsMapping = await loadStarsMapping(db);
  const script = buildNarrationScript(article.fieldData, authorName, ratingFromFieldData(article.fieldData, starsMapping));
  const latest = await loadArticle(db, articleId, slug);
  if (!offlineSource.sameSource(source, offlineSource.captureSource(latest, articleId, slug))) throw new Error("Narration source changed during recipe read");
  return {source, fullText: script.fullText};
}
module.exports = {generateAndPublishNarration, readNarrationScript};
