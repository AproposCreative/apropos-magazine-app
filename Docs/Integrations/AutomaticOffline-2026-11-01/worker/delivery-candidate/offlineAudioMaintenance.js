// Local, SDK-free candidate. Adapters are explicit capabilities, never ambient SDKs.
// Integrate the queue route BEFORE the legacy AI route: a human job must never reach TTS.
const {createHash, randomUUID} = require("node:crypto");
const {contentRevision} = require("./webflowCatalog");
const {isEnglishMirror} = require("./articleLocale");
const {humanRender, publishHumanReplacement} = require("./humanAudioPublishing");
const {createManifestJobStore, COLLECTION: MANIFEST_COLLECTION, DOCUMENT: MANIFEST_DOCUMENT} = require("./manifestReconciliation");

const COLLECTION = "narration_queue";
const ID = /^[a-f\d]{24}$/, REV = /^cms-sha256-v1:[a-f\d]{64}$/, HASH = /^[a-f\d]{64}$/;
// Published Webflow slugs legitimately contain repeated hyphens. Keep the exact
// spelling for storage/source binding; only the legacy episode ID compacts it.
const GENERATION = /^[1-9]\d*$/, SLUG = /^[a-z0-9]+(?:-+[a-z0-9]+)*$/;
const legacyEpisodeID = slug => `ai-${slug.replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").toLowerCase()}`;
const ACTIONS = new Set(["publish_only", "verified_reuse", "ai_rebuild", "ai_create", "human_immutable_copy"]);
const isAIWork = work => work.action === "ai_rebuild" || work.action === "ai_create";
const audioPrefixes = source => [`podcasts/narration/${source.articleSlug}/`, `podcasts/articles/${source.articleSlug}/`];
// Actual legacy returns before TTS; do not infer no effect from a generic error or timeout.
const knownNoAudioEffect = job => ["no_article", "empty", "deferred_quota"].includes(job.status) && job.result === job.status;
const clone = (v) => JSON.parse(JSON.stringify(v));
function canonical(v) {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v && typeof v === "object") return `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}`;
  return JSON.stringify(v);
}
const hash = (v) => createHash("sha256").update(typeof v === "string" || Buffer.isBuffer(v) ? v : canonical(v)).digest("hex");
function freeze(v) {if (v && typeof v === "object") {Object.values(v).forEach(freeze);Object.freeze(v);} return v;}
class MaintenanceSuperseded extends Error {}
class MaintenancePolicyChanged extends Error {}
function requirePolicy(value = {}) {
  const policy = {enabled: value.enabled === true, maxBatch: value.maxBatch ?? 10,
    maxAIRenders: value.maxAIRenders ?? 0, maxAICharacters: value.maxAICharacters ?? 0,
    quotaRetryMs: value.quotaRetryMs ?? 3600000, maxQuotaDeferrals: value.maxQuotaDeferrals ?? 24};
  if (!Number.isSafeInteger(policy.maxBatch) || policy.maxBatch < 1 || policy.maxBatch > 25 ||
      !Number.isSafeInteger(policy.maxAIRenders) || policy.maxAIRenders < 0 || policy.maxAIRenders > 25 ||
      !Number.isSafeInteger(policy.maxAICharacters) || policy.maxAICharacters < 0 || policy.maxAICharacters > 1000000 ||
      !Number.isSafeInteger(policy.quotaRetryMs) || policy.quotaRetryMs < 60000 || policy.quotaRetryMs > 86400000 ||
      !Number.isSafeInteger(policy.maxQuotaDeferrals) || policy.maxQuotaDeferrals < 1 || policy.maxQuotaDeferrals > 100) throw new Error("Invalid maintenance policy");
  return policy;
}
function sourceOf(article) {
  const slug = article?.fieldData?.slug;
  if (!ID.test(article?.id || "") || typeof slug !== "string" || !SLUG.test(slug) || slug.length > 240 ||
      article.isDraft !== false || article.isArchived === true || article.publicationState === "withdrawn" ||
      isEnglishMirror(article.id, article) || typeof article.lastPublished !== "string" || !Number.isFinite(Date.parse(article.lastPublished)) ||
      !REV.test(article.contentRevision || "") || article.contentRevision !== contentRevision(article)) throw new Error("No exact published source");
  // Established DA mirrors may lack source/sourceCollectionId/publicationState.
  return {articleId: article.id, articleSlug: slug, sourceContentRevision: article.contentRevision};
}
function objectIdentity(object) {
  if (!object || typeof object.path !== "string" || object.path.includes("..") ||
      !GENERATION.test(String(object.generation)) || !GENERATION.test(String(object.metageneration)) ||
      !Number.isSafeInteger(Number(object.size)) || Number(object.size) < 1 || Number(object.size) > 256 * 1024 * 1024) throw new Error("Invalid exact media object");
  return {path: object.path, generation: String(object.generation), metageneration: String(object.metageneration),
    size: Number(object.size), metadataHash: hash(object.metadata || {}), sidecarHash: hash(object.sidecar || null)};
}
function pathFromURL(value, bucket) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.hash) return null;
    if (url.hostname === "firebasestorage.googleapis.com") {
      const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(url.pathname);
      if (match && decodeURIComponent(match[1]) === bucket && url.searchParams.get("alt") === "media") return decodeURIComponent(match[2]);
    }
    if (url.hostname === "storage.googleapis.com" && url.pathname.startsWith(`/${bucket}/`)) return decodeURIComponent(url.pathname.slice(bucket.length + 2));
  } catch {}
  return null;
}
function validBinding(object, source) {
  try {
    const identity = objectIdentity(object);
    const metadata = object.metadata || {};
    if (metadata.podcastSchema === "2") return metadata.sourceArticleId === source.articleId &&
      metadata.sourceContentRevision === source.sourceContentRevision && HASH.test(metadata.audioSHA256 || "") &&
      object.path.startsWith(`podcasts/articles/${source.articleSlug}/render-${metadata.audioSHA256}-`) &&
      object.path.endsWith(".m4a") && Number.isFinite(Date.parse(metadata.humanSourcePublishedAt));
    const binding = JSON.parse(metadata.offlineAudioBinding || "null");
    const keys = ["articleId", "articleSlug", "sourceContentRevision", "version", "audioSHA256", "audioBytes", "objectPath"];
    return binding && Object.keys(binding).length === keys.length && keys.every(k => Object.hasOwn(binding, k)) &&
      binding.version === 1 && binding.articleId === source.articleId && binding.articleSlug === source.articleSlug &&
      binding.sourceContentRevision === source.sourceContentRevision && HASH.test(binding.audioSHA256 || "") &&
      binding.audioBytes === identity.size && binding.objectPath === object.path &&
      object.path === `podcasts/narration/${source.articleSlug}/${source.articleSlug}--cms-${source.sourceContentRevision.slice(14)}--${binding.audioSHA256}.m4a` &&
      object.sidecar?.objectGeneration === identity.generation && canonical(object.sidecar.sourceBinding) === canonical(binding);
  } catch {return false;}
}
function trustedEvidence(rows, object, source, verify, kind) {
  if (typeof verify !== "function") return null;
  const candidates = (rows || []).filter(p => p?.kind === kind && p.articleId === source.articleId &&
    p.sourceContentRevision === source.sourceContentRevision && p.objectPath === object.path &&
    String(p.objectGeneration) === String(object.generation) && String(p.objectMetageneration) === String(object.metageneration) &&
    p.audioBytes === Number(object.size) && HASH.test(p.audioSHA256 || "") && p.container === "m4a" && /\.m4a$/i.test(object.path));
  // Inject a verifier rooted in actual historical job/attachment evidence. A boolean in the snapshot is not proof.
  return candidates.length === 1 && verify(clone(candidates[0]), clone(objectIdentity(object)), clone(source)) === true ? clone(candidates[0]) : null;
}
function qualifyPublishedHumanAttachment({snapshot, episodeID, bytes}) {
  // Existing human intake publishes this exact canonical-slug folder and manifest row.
  // This is attachment authority, not a claim that a human read current HTML verbatim.
  if (snapshot?.complete !== true || !Buffer.isBuffer(bytes)) throw new Error("Complete human attachment snapshot required");
  const rows = snapshot.catalog?.episodes?.filter(row => row.id === episodeID);
  if (rows?.length !== 1 || rows[0].kind === "ai") throw new Error("Unique published human row required");
  const row = rows[0], articles = snapshot.articles.filter(a => a.fieldData?.slug === row.articleSlug);
  if (typeof row.publishedAt !== "string" || !Number.isFinite(Date.parse(row.publishedAt))) throw new Error("Exact published human recording timestamp required");
  if (articles.length !== 1) throw new Error("Unique canonical human article required");
  const source = sourceOf(articles[0]), path = pathFromURL(row.audioURL, snapshot.bucket);
  if ((row.articleId && row.articleId !== source.articleId) ||
      !path?.startsWith(`podcasts/articles/${source.articleSlug}/`) ||
      !/^[^/]+\.m4a$/i.test(path.slice(`podcasts/articles/${source.articleSlug}/`.length))) throw new Error("Human intake path/identity mismatch");
  const objects = snapshot.objects.filter(o => o.path === path);
  if (objects.length !== 1 || Number(objects[0].size) !== bytes.length || bytes.length < 12 ||
      bytes.subarray(4, 8).toString("ascii") !== "ftyp") throw new Error("Exact M4A bytes required; other input needs existing encoder");
  const object = objectIdentity(objects[0]);
  return freeze({kind: "human_attachment", authority: "published-human-storage-v1", articleId: source.articleId,
    sourceContentRevision: source.sourceContentRevision, objectPath: path, objectGeneration: object.generation,
    objectMetageneration: object.metageneration, audioBytes: bytes.length, audioSHA256: hash(bytes), container: "m4a",
    sourcePublishedAt: row.publishedAt, manifestRowSHA256: hash(row),
    metadata: {title: row.title || "", hosts: Array.isArray(row.hosts) ? clone(row.hosts) : []}});
}
function workIdentity(work) {
  return {action: work.action, bucket: work.bucket, source: work.source, original: work.original,
    targetID: work.targetID, targetHash: work.targetHash, evidence: work.evidence || null,
    candidate: work.candidate || null, characters: work.characters, renderBudget: work.renderBudget || null,
    oldSource: work.oldSource || null, vacancy: work.vacancy || null, newEpisode: work.newEpisode || null};
}
function renderBudgetOf(qualified, source) {
  // The adapter must use the EXISTING producer recipe, including author, ratings,
  // title, subtitle, intro and outro. Content length is not a provider-character budget.
  if (canonical(qualified?.source) !== canonical(source) || typeof qualified?.fullText !== "string" ||
      qualified.fullText.length < 50 || qualified.fullText.length > 1000000) throw new Error("Exact narration script qualification required");
  return {characters: qualified.fullText.length, scriptSHA256: hash(qualified.fullText)};
}
function workKey(work) {return `offline-v1-${hash(workIdentity(work))}`;}
function validateWork(work) {
  if (!work || !ACTIONS.has(work.action) || typeof work.bucket !== "string" || !work.bucket || !ID.test(work.source?.articleId || "") ||
      !REV.test(work.source.sourceContentRevision || "") || !SLUG.test(work.source.articleSlug || "") ||
      typeof work.targetID !== "string" || !work.targetID ||
      !Number.isSafeInteger(work.characters) || work.characters < 0 || work.key !== workKey(work)) throw new Error("Invalid maintenance work");
  if (work.action === "ai_create") {
    if (work.original !== null || work.targetHash !== null || work.oldSource || work.targetID !== legacyEpisodeID(work.source.articleSlug) ||
        canonical(work.vacancy) !== canonical({targetID: work.targetID, prefixes: audioPrefixes(work.source), completeQueueInventory: true}) ||
        work.newEpisode?.id !== work.targetID || work.newEpisode?.articleId !== work.source.articleId ||
        work.newEpisode?.articleSlug !== work.source.articleSlug || work.newEpisode?.sourceContentRevision !== work.source.sourceContentRevision ||
        work.newEpisode?.kind !== "ai") throw new Error("Exact vacant create scope required");
  } else if (!HASH.test(work.targetHash || "") || !GENERATION.test(work.original?.generation || "") ||
      !GENERATION.test(work.original?.metageneration || "")) throw new Error("Original media identity required");
  if (work.action === "ai_rebuild" && (!work.original.path.startsWith(`podcasts/narration/${work.source.articleSlug}/`) ||
      !/^[^/]+\.(m4a|mp3|aac|wav|mp4)$/i.test(work.original.path.slice(`podcasts/narration/${work.source.articleSlug}/`.length)) ||
      (/--cms-/.test(work.original.path) && (!work.oldSource || work.oldSource.articleId !== work.source.articleId ||
        work.oldSource.articleSlug !== work.source.articleSlug || !REV.test(work.oldSource.sourceContentRevision || "") ||
        work.oldSource.sourceContentRevision === work.source.sourceContentRevision)))) throw new Error("Verified original repair input required");
  if (isAIWork(work) && (!HASH.test(work.renderBudget?.scriptSHA256 || "") ||
      work.renderBudget.characters !== work.characters || work.characters < 50)) throw new Error("Qualified render budget required");
  return work;
}
function planOfflineAudioMaintenance({snapshot, policy, verifyHistoricalProof, verifyHumanAttachment, qualifyNarration}) {
  const limits = requirePolicy(policy);
  if (snapshot?.version !== 1 || snapshot.complete !== true || typeof snapshot.bucket !== "string" || !snapshot.bucket ||
      !Array.isArray(snapshot.articles) || snapshot.articles.length > 10000 || !Array.isArray(snapshot.catalog?.episodes) ||
      snapshot.catalog.episodes.length > 4096 || !Array.isArray(snapshot.objects) || snapshot.objects.length > 20000) throw new Error("Complete bounded inventory required");
  const episodes = snapshot.catalog.episodes, objects = new Map(), sources = new Map(), conflicts = new Set();
  for (const object of snapshot.objects) {
    if (objects.has(object.path)) {conflicts.add(object.path);continue;}
    objects.set(object.path, object);
  }
  for (const article of snapshot.articles) {
    try {
      const source = sourceOf(article);
      const entry = {article, source};
      for (const key of [`id:${source.articleId}`, `slug:${source.articleSlug}`]) {
        if (sources.has(key)) {conflicts.add(key);continue;}
        sources.set(key, entry);
      }
    } catch {} // Invalid/unpublished sources cannot authorize media work.
  }
  const rawIDs = new Set();
  for (const article of snapshot.articles) {
    if (rawIDs.has(article?.id)) conflicts.add(`id:${article.id}`);
    rawIDs.add(article?.id);
  }
  const idCounts = new Map();for (const row of episodes) idCounts.set(row.id, (idCounts.get(row.id) || 0) + 1);
  const rows = [], works = [];
  for (let index = 0; index < episodes.length; index++) {
    const row = episodes[index], entry = {index, episodeID: row.id, kind: row.kind === "ai" ? "ai" : "human"};
    const block = reason => rows.push({...entry, action: "blocked", reason});
    if (typeof row.id !== "string" || idCounts.get(row.id) !== 1) {block("ambiguous_episode_id");continue;}
    const byID = row.articleId ? sources.get(`id:${row.articleId}`) : null;
    const bySlug = sources.get(`slug:${row.articleSlug}`);
    if (!bySlug || (row.articleId && byID !== bySlug) || conflicts.has(`id:${bySlug.source.articleId}`) ||
        conflicts.has(`slug:${bySlug.source.articleSlug}`)) {block("no_unique_published_source");continue;}
    const {article, source} = bySlug, path = pathFromURL(row.audioURL, snapshot.bucket), object = objects.get(path);
    if (!object || conflicts.has(path) || !(path.startsWith(`podcasts/${entry.kind === "ai" ? "narration" : "articles"}/${source.articleSlug}/`))) {block("no_exact_object");continue;}
    let original;try {original = objectIdentity(object);} catch {block("invalid_object_identity");continue;}
    if (validBinding(object, source) && row.articleId === source.articleId && row.sourceContentRevision === source.sourceContentRevision) {
      rows.push({...entry, action: "current_bound"});continue;
    }
    // Complete immutable orphans can be published without another provider call.
    const candidates = snapshot.objects.filter(o => !conflicts.has(o.path) && o.path !== path &&
      o.path.startsWith(`podcasts/${entry.kind === "ai" ? "narration" : "articles"}/${source.articleSlug}/`) && validBinding(o, source));
    let action, candidate, evidence, oldSource;
    if (candidates.length > 1) {block("ambiguous_bound_candidates");continue;}
    if (validBinding(object, source)) {action = "publish_only";candidate = original;}
    else if (candidates.length === 1) {action = "publish_only";candidate = objectIdentity(candidates[0]);}
    else if (entry.kind === "human") {
      evidence = trustedEvidence(snapshot.humanAttachments, object, source, verifyHumanAttachment, "human_attachment");
      if (!evidence) {block("human_attachment_proof_required");continue;}
      action = "human_immutable_copy";
    } else {
      evidence = trustedEvidence(snapshot.historicalProofs, object, source, verifyHistoricalProof, "ai_render");
      if (evidence) action = "verified_reuse";
      else if (!/--cms-/.test(path)) action = "ai_rebuild";
      else {
        try {
          const old = JSON.parse(object.metadata?.offlineAudioBinding || "null");
          oldSource = {articleId: source.articleId, articleSlug: source.articleSlug, sourceContentRevision: old?.sourceContentRevision};
          if (!REV.test(oldSource.sourceContentRevision || "") || oldSource.sourceContentRevision === source.sourceContentRevision ||
              !validBinding(object, oldSource)) throw new Error("No old binding");
          action = "ai_rebuild";
        } catch {block("incomplete_bound_object_requires_readback");continue;}
      }
    }
    const body = article.fieldData?.content;
    if (action === "ai_rebuild" && (typeof body !== "string" || !body.trim())) {block("no_renderable_body");continue;}
    if (action === "ai_rebuild" && row.id !== legacyEpisodeID(source.articleSlug)) {
      block("legacy_repair_target_id_incompatible");continue;
    }
    let renderBudget;
    if (action === "ai_rebuild") {
      try {renderBudget = renderBudgetOf(qualifyNarration?.({article: clone(article), source: clone(source)}), source);}
      catch {block("render_script_qualification_required");continue;}
    }
    const work = {action, bucket: snapshot.bucket, source, original, targetID: row.id, targetHash: hash(row),
      characters: renderBudget?.characters || 0, ...(renderBudget ? {renderBudget} : {}),
      ...(candidate ? {candidate} : {}), ...(evidence ? {evidence} : {}), ...(oldSource ? {oldSource} : {})};
    work.key = workKey(work);validateWork(work);works.push(work);rows.push({...entry, action, key: work.key});
  }
  const targetCounts = new Map();
  for (const [key, {source}] of sources) if (key.startsWith("id:")) {
    const target = legacyEpisodeID(source.articleSlug);targetCounts.set(target, (targetCounts.get(target) || 0) + 1);
  }
  // Recover genuinely missed normal creation as well as already-published legacy rows.
  // Vacancy is a proof obligation, not a fabricated old object/generation.
  for (const [key, {article, source}] of sources) {
    if (!key.startsWith("id:") || conflicts.has(key) || conflicts.has(`slug:${source.articleSlug}`)) continue;
    const prefixes = audioPrefixes(source), targetID = legacyEpisodeID(source.articleSlug);
    const hasRow = episodes.some(row => row.articleId === source.articleId || row.articleSlug === source.articleSlug ||
      prefixes.some(prefix => pathFromURL(row.audioURL, snapshot.bucket)?.startsWith(prefix)));
    if (hasRow) continue;
    const entry = {index: null, episodeID: targetID, articleID: source.articleId, kind: "ai", catalogAbsent: true};
    const block = reason => rows.push({...entry, action: "blocked", reason});
    if (targetCounts.get(targetID) !== 1 || idCounts.has(targetID)) {block("ambiguous_new_episode_id");continue;}
    if (snapshot.objects.some(object => prefixes.some(prefix => object.path?.startsWith(prefix)))) {block("unpublished_audio_requires_readback");continue;}
    if (snapshot.queueInventoryComplete !== true || !Array.isArray(snapshot.audioJobs) || snapshot.audioJobs.length > 20000) {
      block("complete_audio_queue_inventory_required");continue;
    }
    if (typeof article.fieldData.content !== "string" || !article.fieldData.content.trim()) {block("no_renderable_body");continue;}
    let renderBudget;
    try {renderBudget = renderBudgetOf(qualifyNarration?.({article: clone(article), source: clone(source)}), source);}
    catch {block("render_script_qualification_required");continue;}
    const work = {action: "ai_create", bucket: snapshot.bucket, source, original: null, targetID, targetHash: null,
      vacancy: {targetID, prefixes, completeQueueInventory: true}, characters: renderBudget.characters, renderBudget,
      newEpisode: {id: targetID, articleId: source.articleId, articleSlug: source.articleSlug, kind: "ai",
        sourceContentRevision: source.sourceContentRevision, title: String(article.fieldData.name || source.articleSlug),
        subtitle: "Lyt til artiklen", hosts: ["Apropos Magazine"], publishedAt: article.lastPublished}};
    work.key = workKey(work);validateWork(work);
    const ownJobs = snapshot.audioJobs.filter(record => {
      if (record.id !== work.key) return false;
      const job = record?.data && typeof record.data === "object" ? record.data : record;
      try {return storedWork(job, work.key).key === work.key;} catch {return false;}
    });
    const conflict = snapshot.audioJobs.some(record => {
      const job = record?.data && typeof record.data === "object" ? record.data : record;
      if (job.articleId !== source.articleId && job.slug !== source.articleSlug) return false;
      if (knownNoAudioEffect(job)) return false;
      if (ownJobs.length === 1 && record.id === source.articleSlug && job.slug === source.articleSlug &&
          job.articleId === source.articleId && job.status === "offline_reserved" && job.offlineMaintenanceReservation === work.key) return false;
      // Reconstruct this exact existing job; do not treat a copied key, status or
      // articleId as proof. Processing/error receipts remain non-executable in store.
      try {return record.id !== work.key || storedWork(job, work.key).key !== work.key;}
      catch {return true;}
    });
    if (conflict) {block("existing_audio_job_requires_readback");continue;}
    works.push(work);rows.push({...entry, action: work.action, key: work.key});
  }
  const fingerprint = hash({version: 1, bucket: snapshot.bucket, rows, works});
  return freeze({version: 1, fingerprint, bucket: snapshot.bucket, enabled: limits.enabled, rows, works,
    inventory: {raw: episodes.length, uniqueIDs: idCounts.size, canonical: [...sources.keys()].filter(k => k.startsWith("id:")).length,
      missingRows: rows.filter(r => r.catalogAbsent).length,
      ai: rows.filter(r => r.kind === "ai").length, human: rows.filter(r => r.kind === "human").length,
      currentBound: rows.filter(r => r.action === "current_bound").length,
      blocked: rows.filter(r => r.action === "blocked").length}});
}

function payloadFor(work) {
  validateWork(work);
  return {slug: work.source.articleSlug, articleId: work.source.articleId, status: "pending", noNotify: true,
    ...(work.action === "ai_rebuild" ? {offlineRepair: {articleId: work.source.articleId,
      sourceContentRevision: work.source.sourceContentRevision, oldObjectPath: work.original.path,
      oldObjectGeneration: work.original.generation}} : {}),
    offlineMaintenance: {version: 1, key: work.key, work: clone(work)}};
}
function storedWork(data, key) {
  const work = data?.offlineMaintenance?.work;
  validateWork(work);
  if (data.offlineMaintenance.version !== 1 || data.offlineMaintenance.key !== key || work.key !== key ||
      data.slug !== work.source.articleSlug || data.articleId !== work.source.articleId || data.noNotify !== true ||
      canonical(data.offlineRepair || null) !== canonical(payloadFor(work).offlineRepair || null)) throw new Error("Queue work identity changed");
  return work;
}
function createLegacyMaintenanceStore({db, now = Date.now, token = randomUUID, aggregateCharacterLimit}) {
  const aggregateEnabled = aggregateCharacterLimit !== undefined, budgetID = "automatic-offline-v1";
  if (aggregateEnabled && (!Number.isSafeInteger(aggregateCharacterLimit) || aggregateCharacterLimit < 0 || aggregateCharacterLimit > 10000000)) {
    throw new Error("Invalid aggregate AI character limit");
  }
  const budgetRef = db.collection(MANIFEST_COLLECTION).doc(MANIFEST_DOCUMENT);
  const reservationFor = work => ({version: 1, budgetID, characters: work.characters});
  const readBudget = data => {
    const value = data?.offlineMaintenanceBudget;
    if (value === undefined) return {version: 1, budgetID, characters: 0};
    if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).sort().join(",") !== "budgetID,characters,version" ||
        value.version !== 1 || value.budgetID !== budgetID || !Number.isSafeInteger(value.characters) || value.characters < 0 || value.characters > 10000000) return null;
    return value;
  };
  const reserved = (job, work) => !aggregateEnabled || !isAIWork(work) ||
    canonical(job.offlineAICharacterReservation) === canonical(reservationFor(work));
  const ref = key => db.collection(COLLECTION).doc(key);
  const read = async (tx, key) => {const snap = await tx.get(ref(key));return snap.exists ? snap.data() : null;};
  const owns = (data, key, claim) => {
    try {storedWork(data, key);return data.status === "processing" && data.offlineRepairClaim === claim;} catch {return false;}
  };
  return {
    async admit(work, {allowCreate = true} = {}) {
      const payload = payloadFor(work);
      return db.runTransaction(async tx => {
        const current = await read(tx, work.key);
        if (current) {storedWork(current, work.key);return {created: false, status: current.status, key: work.key,
          ready: !Number.isFinite(current.availableAtMs) || current.availableAtMs <= now()};}
        if (allowCreate !== true) return {created: false, status: "budget_blocked", key: work.key};
        if (aggregateEnabled && isAIWork(work)) {
          const budget = readBudget((await tx.get(budgetRef)).data());
          if (!budget) return {created: false, status: "budget_invalid", key: work.key};
          if (work.characters > aggregateCharacterLimit - budget.characters) return {created: false, status: "budget_blocked", key: work.key};
          tx.set(budgetRef, {offlineMaintenanceBudget: {...budget, characters: budget.characters + work.characters}}, {merge: true});
        }
        tx.create(ref(work.key), {...payload, createdAtMs: now(),
          ...(aggregateEnabled && isAIWork(work) ? {offlineAICharacterReservation: reservationFor(work)} : {})});
        return {created: true, status: "pending", key: work.key, ready: true};
      });
    },
    async claim(key) {
      return db.runTransaction(async tx => {
        const current = await read(tx, key);if (!current) return null;
        const work = storedWork(current, key);if (current.status !== "pending" ||
          (Number.isFinite(current.availableAtMs) && current.availableAtMs > now())) return null;
        if (!reserved(current, work)) throw new Error("Exact aggregate reservation required before AI claim");
        if (aggregateEnabled && isAIWork(work)) {
          const budget = readBudget((await tx.get(budgetRef)).data());
          if (!budget || budget.characters < work.characters || budget.characters > aggregateCharacterLimit) throw new Error("Aggregate AI budget authority changed");
        }
        const claim = token();tx.set(ref(key), {status: "processing", offlineRepairClaim: claim, startedAtMs: now()}, {merge: true});
        return {key, claim, work: clone(work)};
      });
    },
    async assertCurrent(key, claim) {
      const data = await db.runTransaction(async tx => {
        const current = await read(tx, key);
        if (!owns(current, key, claim)) throw new MaintenanceSuperseded("Original queue claim changed");
        const work = storedWork(current, key);
        if (!reserved(current, work)) throw new MaintenanceSuperseded("Original aggregate reservation changed");
        if (aggregateEnabled && isAIWork(work)) {
          const budget = readBudget((await tx.get(budgetRef)).data());
          if (!budget || budget.characters < work.characters || budget.characters > aggregateCharacterLimit) throw new MaintenanceSuperseded("Aggregate AI budget authority changed");
        }
        return current;
      });
      if (!data) throw new MaintenanceSuperseded("Original queue claim disappeared");
    },
    async finish(key, claim, status, result) {
      return db.runTransaction(async tx => {
        if (!owns(await read(tx, key), key, claim)) return false;
        tx.set(ref(key), {status, result, processedAtMs: now()}, {merge: true});return true;
      });
    },
    async deferQuota(key, claim, {quotaRetryMs, maxQuotaDeferrals}) {
      return db.runTransaction(async tx => {
        const current = await read(tx, key);if (!owns(current, key, claim)) return false;
        const count = (Number.isSafeInteger(current.quotaDeferrals) ? current.quotaDeferrals : 0) + 1;
        tx.set(ref(key), {status: count > maxQuotaDeferrals ? "error" : "pending",
          result: count > maxQuotaDeferrals ? "quota_deferral_limit" : "deferred_quota", quotaDeferrals: count,
          availableAtMs: now() + quotaRetryMs}, {merge: true});return count <= maxQuotaDeferrals ? "deferred_quota" : "quota_deferral_limit";
      });
    },
  };
}
function currentWorkGuards({work, store, claim, adapters, policy}) {
  return async () => {
    const latestPolicy = requirePolicy(adapters.readRuntimePolicy ? await adapters.readRuntimePolicy() : policy);
    if (!latestPolicy.enabled || (isAIWork(work) && (latestPolicy.maxAIRenders < 1 || work.characters > latestPolicy.maxAICharacters))) {
      throw new MaintenancePolicyChanged("Current runtime numeric budget/gate changed");
    }
    if (adapters.assertRuntimePolicy) await adapters.assertRuntimePolicy();
    await store.assertCurrent(work.key, claim);
    const source = sourceOf(await adapters.readArticle(work.source.articleId));
    if (canonical(source) !== canonical(work.source)) throw new MaintenanceSuperseded("Published source changed");
    if (work.original) {
      const latestObject = await adapters.readObject(work.original.path), object = objectIdentity(latestObject);
      if (canonical(object) !== canonical(work.original)) throw new MaintenanceSuperseded("Original media object changed");
      if (work.oldSource && !validBinding(latestObject, work.oldSource)) throw new MaintenanceSuperseded("Original immutable source proof changed");
    }
    if (isAIWork(work)) {
      const measured = renderBudgetOf(await adapters.readNarrationScript(work), source);
      if (canonical(measured) !== canonical(work.renderBudget)) throw new MaintenanceSuperseded("Original render script/budget changed");
    }
    await store.assertCurrent(work.key, claim);
  };
}

function rendererEpisodeFields(fields, base, work, replacement, bytes) {
  if (fields === undefined) return {};
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) throw new Error("Invalid renderer episode metadata");
  const authoritative = {id: work.targetID, articleId: work.source.articleId, articleSlug: work.source.articleSlug,
    sourceContentRevision: work.source.sourceContentRevision, audioURL: replacement.audioURL, audioBytes: bytes,
    ...(base.kind ? {kind: base.kind} : {})};
  const result = {};
  for (const [key, value] of Object.entries(fields)) {
    if (Object.hasOwn(authoritative, key)) {
      if (value !== authoritative[key]) throw new Error("Renderer metadata changes source/audio identity");
      continue;
    }
    if (["title", "subtitle", "description"].includes(key)) {
      const max = key === "description" ? 20000 : 1000;
      if (typeof value !== "string" || value.length > max || (key === "title" && !value.trim())) throw new Error("Invalid renderer text metadata");
      result[key] = value;
    } else if (key === "hosts") {
      if (!Array.isArray(value) || !value.length || value.length > 20 || value.some(h => typeof h !== "string" || !h.trim() || h.length > 200)) throw new Error("Invalid renderer credits");
      result.hosts = clone(value);
    } else if (key === "publishedAt") {
      if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) throw new Error("Invalid renderer publication date");result[key] = value;
    } else if (key === "guid") {
      if (typeof value !== "string" || !value || value.length > 512 || (base.guid && value !== base.guid)) throw new Error("Renderer cannot change an existing GUID");result.guid = value;
    } else if (key === "imageURL") {
      const url = new URL(value);
      if (typeof value !== "string" || value.length > 4096 || url.protocol !== "https:" || url.username || url.password || url.hash) throw new Error("Invalid renderer image URL");result.imageURL = value;
    } else if (key === "durationSeconds") {
      if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 604800) throw new Error("Invalid measured duration");result.durationSeconds = Math.round(value);
    } else throw new Error("Unknown renderer episode field");
  }
  return result;
}

// A narrow CAS publisher, not the newer catalog-wide selector. IDs/order/unknown fields survive.
async function publishRawReplacement({work, bucket, replacement, assertCurrent, readCatalog, commitCatalog, readObject, assertNoAudio}) {
  await assertCurrent();
  const object = await readObject(replacement.path);
  if (!validBinding(object, work.source) || pathFromURL(replacement.audioURL, bucket) !== replacement.path) throw new Error("Replacement has no immutable source proof");
  const objectBefore = objectIdentity(object), current = await readCatalog();
  const metadata = current.metadata || {};
  if (!GENERATION.test(String(current.generation)) || !GENERATION.test(String(current.metageneration)) ||
      !Array.isArray(current.manifest?.episodes) || metadata.retention || metadata.retentionExpirationTime ||
      metadata.temporaryHold === true || metadata.eventBasedHold === true ||
      (metadata.contentEncoding !== undefined && metadata.contentEncoding !== "identity")) throw new Error("Unsupported raw catalog snapshot");
  const targets = current.manifest.episodes.filter(e => e.id === work.targetID);
  const create = work.action === "ai_create";
  if (create ? targets.length !== 0 : targets.length !== 1 || hash(targets[0]) !== work.targetHash) throw new MaintenanceSuperseded("Original catalog target changed");
  if (create) await assertNoAudio(work, {allowImmutablePath: replacement.path});
  const base = create ? work.newEpisode : targets[0];
  const episode = {...base, ...rendererEpisodeFields(replacement.episode, base, work, replacement, Number(object.size)),
    articleId: work.source.articleId, sourceContentRevision: work.source.sourceContentRevision,
    audioURL: replacement.audioURL, audioBytes: Number(object.size),
    ...(base.kind !== "ai" && object.metadata?.podcastSchema === "2" ? {
      audioObjectGeneration: objectBefore.generation, audioSHA256: object.metadata.audioSHA256,
    } : {})};
  const manifest = {...current.manifest, episodes: create ? [...current.manifest.episodes, episode] :
    current.manifest.episodes.map(e => e.id === work.targetID ? episode : e)};
  const writableMetadata = {};
  for (const key of ["cacheControl", "contentDisposition", "contentEncoding", "contentLanguage", "contentType", "customTime", "temporaryHold", "eventBasedHold"]) {
    if (metadata[key] !== undefined) writableMetadata[key] = metadata[key];
  }
  writableMetadata.metadata = clone(metadata.metadata || {});
  await assertCurrent();
  if (canonical(objectIdentity(await readObject(replacement.path))) !== canonical(objectBefore)) throw new MaintenanceSuperseded("Replacement media changed");
  // Transport must honor BOTH preconditions. A rejected/unknown commit is not retried here.
  const receipt = await commitCatalog({manifest, metadata: writableMetadata,
    ifGenerationMatch: String(current.generation), ifMetagenerationMatch: String(current.metageneration)});
  if (receipt?.published !== true) throw new Error("Catalog commit not acknowledged");
  return {published: true, manifest};
}

async function runMaintenanceJob({key, policy, store, adapters, bucket}) {
  const limits = requirePolicy(adapters.readRuntimePolicy ? await adapters.readRuntimePolicy() : policy);
  if (!limits.enabled) return {status: "disabled"};
  const claimed = await store.claim(key);if (!claimed) return {status: "skipped", key};
  const {work, claim} = claimed, assertCurrent = currentWorkGuards({work, store, claim, adapters, policy});
  let effectStarted = false;
  try {
    if (bucket !== work.bucket) throw new Error("Maintenance bucket changed");
    await assertCurrent();
    const originalCatalog = await adapters.readCatalog();
    const originalTargets = originalCatalog.manifest?.episodes?.filter(e => e.id === work.targetID);
    if (work.action === "ai_create") {
      if (originalTargets?.length !== 0) throw new MaintenanceSuperseded("Vacant catalog target changed before work");
      await adapters.assertNoAudio(work, {allowImmutablePath: null});
    } else if (originalTargets?.length !== 1 || hash(originalTargets[0]) !== work.targetHash) throw new MaintenanceSuperseded("Original catalog target changed before work");
    await assertCurrent();
    let publication;
    if (isAIWork(work)) {
      // Existing legacy repair code freezes its source and verifies old generation again.
      effectStarted = true;
      const generated = await adapters.generateAndPublishNarration({slug: work.source.articleSlug, articleId: work.source.articleId,
        ...(work.action === "ai_rebuild" ? {repair: payloadFor(work).offlineRepair} : {create: true}),
        maintenanceWork: freeze(clone(work)), renderBudget: clone(work.renderBudget),
        ...(work.oldSource ? {oldSource: work.oldSource} : {}), assertCurrent, noNotify: true});
      // This exact existing return occurs BEFORE workDir/TTS; unlike an exception,
      // it is authoritative no-paid-effect evidence and may be retried after cooldown.
      if (generated?.status === "deferred_quota") {
        await assertCurrent();return {status: await store.deferQuota(key, claim, limits) || "stale", key};
      }
      if (generated?.status !== "published") throw new Error("AI repair not published");
      publication = generated.publication;
    } else {
      let replacement;
      if (work.action === "publish_only") {
        const candidate = await adapters.readObject(work.candidate.path);
        if (canonical(objectIdentity(candidate)) !== canonical(work.candidate) || !validBinding(candidate, work.source)) throw new MaintenanceSuperseded("Bound candidate changed");
        replacement = {path: candidate.path, audioURL: await adapters.publicURL(candidate.path)};
      } else {
        // Actual immutable copy, not relabelling the old bytes with today's revision.
        const bytes = await adapters.readAudio(work.original.path, work.original.generation);
        if (!Buffer.isBuffer(bytes) || bytes.length !== work.evidence.audioBytes || hash(bytes) !== work.evidence.audioSHA256 ||
            await adapters.verifyEvidence(work.evidence, work.original, work.source) !== true) throw new Error("Historical/attachment proof does not qualify these bytes");
        await assertCurrent();
        if (work.action === "human_immutable_copy") {
          const source = {sourceArticleId: work.source.articleId, sourceContentRevision: work.source.sourceContentRevision};
          const render = humanRender({slug: work.source.articleSlug, source, digest: hash(bytes),
            metadata: work.evidence.metadata || {}, sourcePublishedAt: work.evidence.sourcePublishedAt});
          const audioURL = await adapters.publicURL(render.path, render.token);
          publication = await publishHumanReplacement({render, source,
            readSource: async () => {await assertCurrent();return source;}, assertInput: assertCurrent,
            upload: async (actualRender, options) => {effectStarted = true;await adapters.uploadHuman(actualRender, bytes, options);},
            audioURL, publishManifest: guard => publishRawReplacement({work, bucket,
              replacement: {path: render.path, audioURL}, assertCurrent: guard, ...adapters})});
        } else {
          // Existing historical proof must bind the old render to this exact revision.
          effectStarted = true;
          const audioSHA256 = hash(bytes);
          const path = `podcasts/narration/${work.source.articleSlug}/${work.source.articleSlug}--cms-${work.source.sourceContentRevision.slice(14)}--${audioSHA256}.m4a`;
          const binding = {...work.source, version: 1, audioSHA256, audioBytes: bytes.length, objectPath: path};
          const token = randomUUID();
          const uploaded = await adapters.uploadAI({path, token, metadata: {offlineAudioBinding: JSON.stringify(binding)}}, bytes, {ifGenerationMatch: 0});
          if (!GENERATION.test(String(uploaded?.generation)) || Number(uploaded.size) !== bytes.length) throw new Error("Immutable copy not acknowledged");
          await assertCurrent();
          await adapters.writeSidecar(`${path}.json`, {sourceBinding: binding, objectGeneration: String(uploaded.generation)}, {ifGenerationMatch: 0});
          replacement = {path, audioURL: await adapters.publicURL(path, token)};
        }
      }
      if (!publication) {await assertCurrent();effectStarted = true;
        publication = await publishRawReplacement({work, bucket, replacement, assertCurrent, ...adapters});}
    }
    await assertCurrent();
    const proposedTarget = publication?.manifest?.episodes?.filter(e => e.id === work.targetID);
    // A commit acknowledgement/proposed payload cannot substitute for actual Storage readback.
    publication = await adapters.readPublication(work);
    const actualTarget = publication?.manifest?.episodes?.filter(e => e.id === work.targetID);
    if (proposedTarget && (proposedTarget.length !== 1 || actualTarget?.length !== 1 ||
        hash(proposedTarget[0]) !== hash(actualTarget[0]))) throw new Error("Actual catalog differs from exact committed target");
    const accepted = publication?.published === true && publication.manifest?.episodes?.filter(e => e.id === work.targetID &&
      e.articleId === work.source.articleId && e.sourceContentRevision === work.source.sourceContentRevision).length === 1;
    if (!accepted || await adapters.verifyPublication(work, publication) !== true) throw new Error("No exact publication readback");
    await assertCurrent();
    return {status: await store.finish(key, claim, "done", "published") ? "done" : "stale", key};
  } catch (error) {
    if (!effectStarted && error instanceof MaintenancePolicyChanged) {
      return {status: await store.finish(key, claim, "pending", "budget_blocked") ? "budget_blocked" : "stale", key};
    }
    // Paid/Storage/CAS uncertainty is parked in the SAME queue. Never reset it to pending.
    const result = error instanceof MaintenanceSuperseded ? "superseded" : effectStarted ? "needs_readback" : "blocked";
    return {status: await store.finish(key, claim, "error", result) ? result : "stale", key};
  }
}
async function dispatchMaintenanceBatch({plan, cursor, policy, store}) {
  const limits = requirePolicy(policy);
  if (!limits.enabled) return {status: "disabled", cursor: cursor || null, receipts: []};
  if (plan?.version !== 1 || !Array.isArray(plan.works) || !HASH.test(plan.fingerprint || "") ||
      plan.fingerprint !== hash({version: 1, bucket: plan.bucket, rows: plan.rows, works: plan.works}) ||
      (cursor && (cursor.fingerprint !== plan.fingerprint || !Number.isSafeInteger(cursor.offset) || cursor.offset < 0 || cursor.offset > plan.works.length))) throw new Error("Invalid finite plan cursor");
  let offset = cursor?.offset || 0, renders = 0, characters = 0, budgetBlocked = 0;
  const receipts = [];
  while (offset < plan.works.length && receipts.length < limits.maxBatch) {
    const work = validateWork(plan.works[offset]);
    const allowCreate = !isAIWork(work) || (renders < limits.maxAIRenders && characters + work.characters <= limits.maxAICharacters);
    // Dedup and budget admission share one transaction. Existing jobs do not consume
    // another batch reservation, and budget denial never creates a document.
    const receipt = await store.admit(work, {allowCreate});receipts.push(receipt);offset++;
    if (receipt.status === "budget_blocked" || receipt.status === "budget_invalid") budgetBlocked++;
    if (receipt.created && isAIWork(work)) {renders++;characters += work.characters;}
  }
  return {status: offset === plan.works.length ? "complete" : "partial",
    cursor: {fingerprint: plan.fingerprint, offset}, receipts, budgetBlocked, reserved: {renders, characters}};
}
function createAutomaticOfflineEntrypoints({db, policy, loadSnapshot, store = createLegacyMaintenanceStore({db}), adapters, bucket,
  verifyHistoricalProof, verifyHumanAttachment, qualifyNarration}) {
  // Request reuses the existing durable, coalescing manifest wake-up document.
  // Wire onCanonicalCMSChange AFTER the existing canonical write; schedule also supplies fresh inventory.
  const manifestStore = createManifestJobStore({db});
  const manifestRef = db.collection(MANIFEST_COLLECTION).doc(MANIFEST_DOCUMENT);
  const cursorState = () => db.runTransaction(async tx => (await tx.get(manifestRef)).data());
  const entrypoints = {
    async onCanonicalCMSChange() {if (!requirePolicy(policy).enabled) return {status: "disabled"};
      return {status: "requested", token: await manifestStore.request()};},
    async reconcile({cursor} = {}) {
      if (!requirePolicy(policy).enabled) return {status: "disabled", receipts: []};
      let observed = await cursorState();
      if (!observed) {await manifestStore.request();observed = await cursorState();}
      const plan = planOfflineAudioMaintenance({snapshot: await loadSnapshot(), policy, verifyHistoricalProof, verifyHumanAttachment, qualifyNarration});
      const saved = observed.offlineMaintenanceCursor;
      const resume = cursor || (saved?.fingerprint === plan.fingerprint && saved.offset < plan.works.length ? saved : undefined);
      const result = await dispatchMaintenanceBatch({plan, cursor: resume, policy, store});
      const cursorPersisted = await db.runTransaction(async tx => {
        const latest = (await tx.get(manifestRef)).data();
        if (!latest || latest.requestedToken !== observed.requestedToken ||
            canonical(latest.offlineMaintenanceCursor || null) !== canonical(saved || null)) return false;
        tx.set(manifestRef, {offlineMaintenanceCursor: result.cursor}, {merge: true});return true;
      });
      return {plan, ...result, cursorPersisted};
    },
    async onScheduledInventory() {
      const result = await entrypoints.reconcile();
      if (result.status === "disabled") return result;
      // Lost created-event recovery. Queue trigger and schedule share exactly the same original claim.
      // Only one inline media job: do not multiply a 540-second provider path by the scan batch size.
      const pending = result.receipts.find(receipt => receipt.status === "pending" && receipt.ready !== false);
      return {...result, recovery: pending ? await runMaintenanceJob({key: pending.key, policy, store, adapters, bucket}) : null};
    },
    async onQueueCreated(event) {
      const data = event?.data?.data();
      if (!data?.offlineMaintenance) return {handled: false};
      // Recognized jobs are swallowed even while disabled; never fall through to old TTS/human confusion.
      if (!requirePolicy(policy).enabled) return {handled: true, status: "disabled"};
      return {handled: true, ...await runMaintenanceJob({key: event.data.id, policy, store, adapters, bucket})};
    },
  };
  return entrypoints;
}
module.exports = {COLLECTION, MaintenanceSuperseded, sourceOf, objectIdentity, validBinding, pathFromURL,
  qualifyPublishedHumanAttachment, planOfflineAudioMaintenance, payloadFor, createLegacyMaintenanceStore, publishRawReplacement,
  runMaintenanceJob, dispatchMaintenanceBatch, createAutomaticOfflineEntrypoints};
