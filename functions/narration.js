/**
 * Server-side AI-oplæsning (narration).
 *
 * Genskaber præcis recepten fra scripts/narration-poc.mjs:
 *   stemme "Ellen", model eleven_v3, talt intro (+ stjerne) + artikeltekst + outro,
 *   ffmpeg voice-polish EQ + blød stereobredde, baggrundsjingle med musik-intro,
 *   bed under oplæsningen og en svulmende jingle-outro til sidst.
 *
 * Kører i Cloud Functions via ffmpeg-static/ffprobe-static (Linux-binaries hentes
 * ved deploy). Lyd skrives midlertidigt i /tmp og ryddes op bagefter.
 */

const {spawn, execFileSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const ffmpegPath = require("ffmpeg-static");
const ffprobePath = require("ffprobe-static").path;

// ---- Config (matcher narration-poc.mjs) -----------------------------------
const BUCKET = "apropos-magazine-6004a.firebasestorage.app";
const NARRATION_PREFIX = "podcasts/narration/";
const ARTICLES_PREFIX = "podcasts/articles/";
const MANIFEST_PATH = "podcasts/manifest.json";

const VOICE_NAME = "Ellen";
const MODEL_ID = "eleven_v3";
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

function buildNarrationText(fieldData, authorName, rating) {
  const title = String(fieldData.name || "").trim();
  const subtitle = String(fieldData.subtitle || "").trim();
  const intro = htmlToReadableText(fieldData.intro || "");
  const bodyText = htmlToReadableText(fieldData.content || "");

  const introLine = authorName ?
    `Du lytter til artiklen "${title}", skrevet af ${authorName}, ` +
      "indtalt med kunstig intelligens på vegne af Apropos Magazine." :
    `Du lytter til artiklen "${title}", indtalt med kunstig intelligens ` +
      "på vegne af Apropos Magazine.";

  const danishNumbers = ["nul", "en", "to", "tre", "fire", "fem", "seks"];
  const ratingLine = rating >= 1 && rating <= 6 ?
    `Anmeldelsen får ${danishNumbers[rating]} ud af seks stjerner.` : "";
  const outroLine = "Tak fordi du lyttede med på Apropos Magazine.";

  return [introLine, ratingLine, subtitle, intro, bodyText, outroLine]
      .filter(Boolean)
      .join("\n\n");
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

async function synthesizeChunk(apiKey, voiceId, text, outPath) {
  const body = {text, model_id: MODEL_ID};
  const url =
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=${OUTPUT_FORMAT}`;
  const maxAttempts = 3;
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
    return {count, limit, ratio: count / limit};
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

function probeDuration(filePath) {
  const out = execFileSync(ffprobePath, [
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1",
    filePath,
  ]).toString().trim();
  return parseFloat(out) || 0;
}

// Musik-intro (højt) → duck til bed → bed under oplæsning → svulm op til outro.
function mixJingle(voicePath, jinglePath, outPath, voiceDuration) {
  const introLin = dbToLinear(JINGLE_INTRO_GAIN);
  const bedLin = dbToLinear(JINGLE_GAIN);
  const outroLin = dbToLinear(JINGLE_OUTRO_GAIN);
  const duckStart = JINGLE_INTRO_SECS;
  const duckEnd = JINGLE_INTRO_SECS + JINGLE_DUCK;
  const voiceEnd = JINGLE_INTRO_SECS + voiceDuration;
  const riseStart = voiceEnd;
  const riseEnd = voiceEnd + JINGLE_OUTRO_RISE;
  const total = voiceEnd + JINGLE_OUTRO_SECS;
  const fadeOutStart = Math.max(0, total - JINGLE_FADE_OUT);

  const duckExpr =
    `if(lt(t,${duckStart}),${introLin.toFixed(4)},` +
    `if(lt(t,${duckEnd}),${introLin.toFixed(4)}+(${bedLin.toFixed(4)}-${introLin.toFixed(4)})*(t-${duckStart})/${JINGLE_DUCK},` +
    `if(lt(t,${riseStart.toFixed(2)}),${bedLin.toFixed(4)},` +
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

async function produceFinal(listPath, outPath, workDir) {
  const voiceWav = path.join(workDir, "voice.wav");
  await encodeVoiceWav(listPath, voiceWav);
  const duration = probeDuration(voiceWav);
  logger.info(
      `narration mix: intro ${JINGLE_INTRO_SECS}s @ ${JINGLE_INTRO_GAIN}dB → ` +
      `bed ${JINGLE_GAIN}dB → outro ${JINGLE_OUTRO_SECS}s @ ${JINGLE_OUTRO_GAIN}dB, ` +
      `tale ${duration.toFixed(0)}s`,
  );
  await mixJingle(voiceWav, JINGLE_PATH, outPath, duration);
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

async function articleHasAudio(bucket, slug) {
  for (const prefix of [ARTICLES_PREFIX, NARRATION_PREFIX]) {
    try {
      const [files] = await bucket.getFiles({prefix: `${prefix}${slug}/`});
      if (files.some((f) => isAudioFile(f.name))) return true;
    } catch (e) { /* best effort */ }
  }
  return false;
}

async function uploadObject(bucket, localPath, storagePath, token) {
  await bucket.upload(localPath, {
    destination: storagePath,
    metadata: {
      contentType: "audio/mp4",
      cacheControl: "public, max-age=31536000, immutable",
      metadata: {
        firebaseStorageDownloadTokens: token,
        podcastOptimized: "true",
      },
    },
    resumable: true,
  });
}

async function writeNarrationMetadata(bucket, slug, metadata) {
  const metadataPath = `${NARRATION_PREFIX}${slug}/narration.json`;
  const payload = {
    title: metadata.title,
    hosts: metadata.hosts,
    kind: "ai",
    updatedAt: new Date().toISOString(),
  };
  await bucket.file(metadataPath).save(JSON.stringify(payload, null, 2), {
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
    };
  } catch (e) {
    return {title: "", hosts: []};
  }
}

// Regenererer podcasts/manifest.json (port af syncManifest fra podcast-auto-publish.mjs).
async function syncManifest(bucket) {
  const episodes = [];
  const humanSlugs = new Set();

  const humanFiles = await listAudioObjects(bucket, ARTICLES_PREFIX);
  for (const file of humanFiles) {
    const parts = file.name.split("/").filter(Boolean);
    const slug = parts[parts.length - 2];
    if (!slug) continue;
    const [metadata] = await file.getMetadata();
    const token = extractToken(metadata);
    if (!token) continue;
    const meta = await readJsonMetadata(bucket, `${ARTICLES_PREFIX}${slug}/podcast.json`);
    humanSlugs.add(slug);
    episodes.push({
      id: slugToId(slug),
      articleSlug: slug,
      title: meta.title || titleFromSlug(slug),
      subtitle: "Lyt til artiklen",
      audioURL: publicURL(file.name, token),
      hosts: meta.hosts.length ? meta.hosts : ["Apropos Magazine"],
      publishedAt: metadata.updated || metadata.timeCreated || new Date().toISOString(),
    });
  }

  const narrationFiles = await listAudioObjects(bucket, NARRATION_PREFIX);
  for (const file of narrationFiles) {
    const parts = file.name.split("/").filter(Boolean);
    const slug = parts[parts.length - 2];
    if (!slug || humanSlugs.has(slug)) continue;
    const [metadata] = await file.getMetadata();
    const token = extractToken(metadata);
    if (!token) continue;
    const meta = await readJsonMetadata(bucket, `${NARRATION_PREFIX}${slug}/narration.json`);
    episodes.push({
      id: `ai-${slugToId(slug)}`,
      articleSlug: slug,
      title: meta.title || titleFromSlug(slug),
      subtitle: "Lyt til artiklen",
      audioURL: publicURL(file.name, token),
      hosts: meta.hosts.length ? meta.hosts : ["Apropos Magazine"],
      publishedAt: metadata.updated || metadata.timeCreated || new Date().toISOString(),
      kind: "ai",
    });
  }

  episodes.sort((a, b) => new Date(b.publishedAt) - new Date(a.publishedAt));

  let manifestToken = null;
  try {
    const [existing] = await bucket.file(MANIFEST_PATH).getMetadata();
    manifestToken = extractToken(existing);
  } catch (e) {
    manifestToken = null;
  }
  if (!manifestToken) manifestToken = randomUUID();

  const manifest = {version: 1, updatedAt: new Date().toISOString(), episodes};
  await bucket.file(MANIFEST_PATH).save(JSON.stringify(manifest, null, 2), {
    resumable: false,
    metadata: {
      contentType: "application/json",
      cacheControl: "public, max-age=300",
      metadata: {firebaseStorageDownloadTokens: manifestToken},
    },
  });
  logger.info(`narration manifest synced (${episodes.length} episodes)`);
}

async function loadArticle(db, articleId, slug) {
  if (articleId) {
    const doc = await db.collection("articles").doc(String(articleId)).get();
    if (doc.exists) return doc.data();
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
async function generateAndPublishNarration({slug, articleId, name, apiKey}) {
  const db = admin.firestore();
  const bucket = admin.storage().bucket(BUCKET);

  if (await articleHasAudio(bucket, slug)) {
    logger.info(`narration: ${slug} har allerede lyd — springer over`);
    return {status: "exists"};
  }

  const article = await loadArticle(db, articleId, slug);
  if (!article || !article.fieldData) {
    logger.warn(`narration: ingen artikel fundet for ${slug} (${articleId})`);
    return {status: "no_article"};
  }
  const fieldData = article.fieldData;

  const authorName = await resolveAuthorName(db, fieldData.author);
  const starsMapping = await loadStarsMapping(db);
  const rating = ratingFromFieldData(fieldData, starsMapping);
  const fullText = buildNarrationText(fieldData, authorName, rating);

  if (fullText.length < 50) {
    logger.warn(`narration: ${slug} har for lidt tekst (${fullText.length} tegn)`);
    return {status: "empty"};
  }

  // Kredit-cap: stop før ElevenLabs-kvoten brændes.
  const usage = await elevenLabsUsage(apiKey);
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
    const chunks = chunkText(fullText, MAX_CHARS_PER_CHUNK);
    logger.info(`narration: ${slug} — ${fullText.length} tegn → ${chunks.length} chunk(s)`);

    const chunkPaths = [];
    for (let i = 0; i < chunks.length; i++) {
      const chunkPath = path.join(workDir, `chunk-${String(i).padStart(3, "0")}.mp3`);
      await synthesizeChunk(apiKey, voiceId, chunks[i], chunkPath);
      chunkPaths.push(chunkPath);
    }

    const listPath = path.join(workDir, "concat.txt");
    fs.writeFileSync(
        listPath,
        chunkPaths.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join("\n"),
    );

    const outPath = path.join(workDir, `${slugToId(slug)}.m4a`);
    await produceFinal(listPath, outPath, workDir);

    const destPath = `${NARRATION_PREFIX}${slug}/${slug}.m4a`;
    const token = await resolveDownloadToken(bucket, destPath);
    await uploadObject(bucket, outPath, destPath, token);

    const title = String(fieldData.name || "").trim() || titleFromSlug(slug);
    const hosts = authorName ? [authorName] : ["Apropos Magazine"];
    await writeNarrationMetadata(bucket, slug, {title, hosts});

    await syncManifest(bucket);

    logger.info(`narration: udgivet ${slug} → ${publicURL(destPath, token)}`);
    return {status: "published", title};
  } finally {
    try {
      fs.rmSync(workDir, {recursive: true, force: true});
    } catch (e) { /* ignore */ }
  }
}

module.exports = {generateAndPublishNarration};
