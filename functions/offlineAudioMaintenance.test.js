const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {contentRevision} = require("./webflowCatalog");
const {humanRender} = require("./humanAudioPublishing");
const {createManifestJobStore} = require("./manifestReconciliation");
const {COLLECTION, MaintenanceSuperseded, sourceOf, objectIdentity, validBinding, pathFromURL,
  qualifyPublishedHumanAttachment, planOfflineAudioMaintenance: plan, payloadFor, createLegacyMaintenanceStore,
  publishRawReplacement, runMaintenanceJob, dispatchMaintenanceBatch, createAutomaticOfflineEntrypoints} = require("./offlineAudioMaintenance");
const copy = v => structuredClone(v), digest = v => createHash("sha256").update(v).digest("hex");
const bucket = "example.invalid", enabled = {enabled: true, maxBatch: 25, maxAIRenders: 25, maxAICharacters: 100000};
function article(n = 1, body = "<p>Actual published article body.</p>") {
  const row = {id: n.toString(16).padStart(24, "0"), fieldData: {slug: `story-${n}`, name: `Story ${n}`, content: body},
    isDraft: false, isArchived: false, createdOn: "2026-10-01T10:00:00Z", lastPublished: "2026-11-01T08:00:00Z"};
  row.contentRevision = contentRevision(row);return row;
}
// Production must qualify the existing buildNarrationScript's actual fullText.
// This local adapter deliberately includes more than the canonical content body.
const qualifyNarration = ({article: a, source}) => ({source, fullText:
  `Du lytter til artiklen ${a.fieldData.name}.\n\n${a.fieldData.subtitle || ""}\n\n${a.fieldData.intro || ""}\n\n${a.fieldData.content}\n\nTak for at lytte til Apropos Magazine.`});
const url = path => `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=fixture`;
function inventory({count = 1, human = false} = {}) {
  const articles = Array.from({length: count}, (_, i) => article(i + 1));
  const objects = articles.map((a, i) => ({path: `podcasts/${human ? "articles" : "narration"}/${a.fieldData.slug}/old.m4a`,
    generation: String(100 + i), metageneration: "1", size: 5, metadata: {podcastOptimized: "true"}}));
  const episodes = articles.map((a, i) => ({id: `${human ? "podcast" : "ai"}-${a.fieldData.slug}`, articleSlug: a.fieldData.slug,
    title: a.fieldData.name, kind: human ? "human" : "ai", audioURL: url(objects[i].path), arbitraryField: {preserve: i}}));
  return {version: 1, complete: true, bucket, articles, objects, queueInventoryComplete: true, audioJobs: [], catalog: {version: 2, episodes}};
}
function boundAI(a, bytes = Buffer.from("media"), generation = "300") {
  const source = sourceOf(a), sha = digest(bytes);
  const path = `podcasts/narration/${source.articleSlug}/${source.articleSlug}--cms-${source.sourceContentRevision.slice(14)}--${sha}.m4a`;
  const binding = {...source, version: 1, audioSHA256: sha, audioBytes: bytes.length, objectPath: path};
  return {path, generation, metageneration: "1", size: bytes.length, metadata: {offlineAudioBinding: JSON.stringify(binding)},
    sidecar: {objectGeneration: generation, sourceBinding: binding}};
}
function proof(snapshot, human = false) {
  const object = snapshot.objects[0], a = snapshot.articles[0];
  return {kind: human ? "human_attachment" : "ai_render", articleId: a.id, sourceContentRevision: a.contentRevision,
    objectPath: object.path, objectGeneration: object.generation, objectMetageneration: object.metageneration,
    audioBytes: 5, audioSHA256: digest("media"), container: "m4a", sourcePublishedAt: a.lastPublished, proofID: "actual-source-receipt",
    metadata: {title: "Recorded episode", hosts: ["Actual human"]}};
}
function memoryDB() {
  const documents = new Map();let tail = Promise.resolve();
  const ref = path => ({path});
  const snapshot = path => ({exists: documents.has(path), data: () => copy(documents.get(path))});
  const db = {collection: name => ({doc: id => ref(`${name}/${id}`)}), runTransaction: fn => {
    const task = tail.then(async () => {
      let written = false;const staged = [];
      const result = await fn({get: async r => {assert.equal(written, false, "Firestore reads precede writes");return snapshot(r.path);},
        create: (r, value) => {assert.equal(documents.has(r.path), false);written = true;staged.push([r.path, copy(value)]);},
        set: (r, value, options) => {written = true;staged.push([r.path, options?.merge ? {...copy(documents.get(r.path)), ...copy(value)} : copy(value)]);}});
      for (const [path, value] of staged) documents.set(path, value);return result;
    });tail = task.catch(() => {});return task;
  }};
  return {db, documents};
}
function runtime(snapshot = inventory(), options = {}) {
  let clock = 1000;
  const {db, documents} = memoryDB(), store = createLegacyMaintenanceStore({db, now: () => clock});
  const objects = new Map(snapshot.objects.map(o => [o.path, copy(o)]));
  const articles = new Map(snapshot.articles.map(a => [a.id, copy(a)]));
  let catalog = {manifest: copy(snapshot.catalog), generation: "10", metageneration: "2",
    metadata: {contentType: "application/json", cacheControl: "public,max-age=30", metadata: {firebaseStorageDownloadTokens: "fixture", unknown: "keep"}}};
  const calls = [];
  const adapters = {
    readArticle: async id => copy(articles.get(id)), readObject: async path => copy(objects.get(path)),
    readNarrationScript: async work => qualifyNarration({article: articles.get(work.source.articleId), source: work.source}),
    assertNoAudio: async (work, {allowImmutablePath}) => {
      if (catalog.manifest.episodes.some(e => e.id === work.targetID || e.articleId === work.source.articleId || e.articleSlug === work.source.articleSlug) ||
          [...objects.values()].some(o => work.vacancy.prefixes.some(p => o.path.startsWith(p)) && o.path !== allowImmutablePath) ||
          [...documents.entries()].some(([path, job]) => path.startsWith(COLLECTION + "/") && path !== `${COLLECTION}/${work.key}` &&
            (job.articleId === work.source.articleId || job.slug === work.source.articleSlug) &&
            !(path === `${COLLECTION}/${work.source.articleSlug}` && job.status === "offline_reserved" &&
              job.offlineMaintenanceReservation === work.key && documents.get(`${COLLECTION}/${work.key}`)?.offlineMaintenance?.work?.key === work.key))) throw new MaintenanceSuperseded("Audio vacancy changed");
    },
    readCatalog: async () => copy(catalog),
    publicURL: async path => url(path),
    readAudio: async (path, generation) => {calls.push("read-bytes");assert.equal(objects.get(path).generation, generation);return Buffer.from("media");},
    verifyEvidence: async evidence => evidence.proofID === "actual-source-receipt",
    commitCatalog: async command => {
      calls.push("commit");assert.equal(command.ifGenerationMatch, catalog.generation);assert.equal(command.ifMetagenerationMatch, catalog.metageneration);
      catalog = {manifest: copy(command.manifest), metadata: copy(command.metadata), generation: String(Number(catalog.generation) + 1), metageneration: "1"};
      return {published: true};
    },
    uploadHuman: async (render, bytes, conditions) => {
      calls.push("human-upload");assert.deepEqual(conditions, {ifGenerationMatch: 0});assert.equal(objects.has(render.path), false);
      objects.set(render.path, {path: render.path, generation: "500", metageneration: "1", size: bytes.length, metadata: copy(render.metadata)});
    },
    uploadAI: async (render, bytes, conditions) => {
      calls.push("ai-copy");assert.deepEqual(conditions, {ifGenerationMatch: 0});assert.equal(objects.has(render.path), false);
      const result = {path: render.path, generation: "501", metageneration: "1", size: bytes.length, metadata: copy(render.metadata)};
      objects.set(render.path, result);return copy(result);
    },
    writeSidecar: async (path, value, conditions) => {
      calls.push("sidecar");assert.deepEqual(conditions, {ifGenerationMatch: 0});objects.get(path.slice(0, -5)).sidecar = copy(value);
    },
    generateAndPublishNarration: async ({articleId, slug, repair, create, maintenanceWork, renderBudget, assertCurrent, noNotify}) => {
      calls.push("provider");assert.equal(noNotify, true);assert.equal(Object.isFrozen(maintenanceWork), true);
      if (!create) assert.deepEqual(Object.keys(repair).sort(), ["articleId", "oldObjectGeneration", "oldObjectPath", "sourceContentRevision"]);
      const actualScript = qualifyNarration({article: articles.get(articleId), source: sourceOf(articles.get(articleId))}).fullText;
      assert.deepEqual(renderBudget, {characters: actualScript.length, scriptSHA256: digest(actualScript)});
      if (!create) {assert.equal(repair.articleId, articleId);assert.equal(repair.oldObjectGeneration, objects.get(repair.oldObjectPath).generation);}
      await assertCurrent();const object = boundAI(articles.get(articleId));objects.set(object.path, object);
      const source = sourceOf(articles.get(articleId));
      if (create) {
        await publishRawReplacement({work: maintenanceWork, bucket, replacement: {path: object.path, audioURL: url(object.path)}, assertCurrent, ...adapters});
        return {status: "published"};
      }
      catalog.manifest.episodes = catalog.manifest.episodes.map(e => e.id === `ai-${slug}` ?
        {...e, articleId, sourceContentRevision: source.sourceContentRevision, audioURL: url(object.path), audioBytes: object.size} : e);
      return {status: "published"};
    },
    readPublication: async () => ({published: true, manifest: copy(catalog.manifest)}),
    verifyPublication: async (work, publication) => {
      const row = publication.manifest.episodes.find(e => e.id === work.targetID);
      return !!row && validBinding(objects.get(pathFromURL(row.audioURL, bucket)), work.source);
    },
  };
  Object.assign(adapters, options.adapters);
  return {db, documents, store, objects, articles, adapters, calls, catalog: () => catalog,
    advance: ms => {clock += ms;},
    setCatalog: next => {catalog = next;},
    job: key => documents.get(`${COLLECTION}/${key}`),
    run: key => runMaintenanceJob({key, policy: enabled, store, adapters, bucket})};
}
function planned(snapshot, extra = {}) {return plan({snapshot, policy: enabled, qualifyNarration, ...extra});}

test("default is off and disabled entrypoints do not even read inventory or DB", async () => {
  const p = plan({snapshot: inventory()});assert.equal(p.enabled, false);assert.equal(p.works.length, 0);
  assert.equal(p.rows[0].reason, "render_script_qualification_required");
  const entry = createAutomaticOfflineEntrypoints({db: {collection: () => ({doc: () => ({})})},
    loadSnapshot: () => assert.fail("disabled read"), store: {admit: () => assert.fail("disabled write")}});
  assert.equal((await entry.onCanonicalCMSChange()).status, "disabled");assert.equal((await entry.reconcile()).status, "disabled");
  assert.deepEqual(await dispatchMaintenanceBatch({plan: p}), {status: "disabled", cursor: null, receipts: []});
});
test("unproven optimized legacy audio requires AI rebuild; no fabricated current hash", () => {
  const s = inventory(), p = planned(s), work = p.works[0];
  assert.equal(work.action, "ai_rebuild");assert.equal(p.inventory.currentBound, 0);
  assert.equal(work.evidence, undefined);assert.equal(s.catalog.episodes[0].sourceContentRevision, undefined);
  assert.equal(work.source.sourceContentRevision, contentRevision(s.articles[0]));
  assert.equal(work.key, planned(copy(s)).works[0].key);assert.equal(Object.isFrozen(work.original), true);
});
test("exact immutable AI object, metadata and sidecar plus row is a no-op", () => {
  const s = inventory(), object = boundAI(s.articles[0]);s.objects = [object];
  Object.assign(s.catalog.episodes[0], {audioURL: url(object.path), articleId: s.articles[0].id, sourceContentRevision: s.articles[0].contentRevision});
  assert.equal(planned(s).rows[0].action, "current_bound");assert.equal(planned(s).works.length, 0);
  s.objects[0].sidecar.objectGeneration = "wrong";
  assert.equal(planned(s).rows[0].reason, "incomplete_bound_object_requires_readback");
});
test("complete orphan is publish-only; multiple current candidates cannot pick arbitrarily", () => {
  const s = inventory();s.objects.push(boundAI(s.articles[0]));
  assert.equal(planned(s).works[0].action, "publish_only");
  s.objects.push(boundAI(s.articles[0], Buffer.from("other"), "301"));
  assert.equal(planned(s).rows[0].reason, "ambiguous_bound_candidates");
});
test("old source-bound AI keeps OLD proof separate from NEW source for the narrow worker adapter", () => {
  const s = inventory(), previous = copy(s.articles[0]), object = boundAI(previous);s.objects = [object];s.catalog.episodes[0].audioURL = url(object.path);
  s.articles[0] = article(1, "Current correction");
  const work = planned(s).works[0];assert.equal(work.action, "ai_rebuild");
  assert.equal(work.oldSource.sourceContentRevision, previous.contentRevision);
  assert.equal(work.source.sourceContentRevision, s.articles[0].contentRevision);
  assert.notEqual(work.oldSource.sourceContentRevision, work.source.sourceContentRevision);
  assert.equal(work.original.path, object.path);
});
test("historical reuse needs exact source, object, bytes and external trusted verifier", () => {
  const s = inventory();s.historicalProofs = [proof(s)];
  assert.equal(planned(s).works[0].action, "ai_rebuild");
  assert.equal(planned(s, {verifyHistoricalProof: () => true}).works[0].action, "verified_reuse");
  for (const delta of [{sourceContentRevision: "cms-sha256-v1:" + "a".repeat(64)}, {objectGeneration: "999"}, {audioSHA256: "bad"}, {objectMetageneration: "2"}]) {
    const changed = copy(s);Object.assign(changed.historicalProofs[0], delta);
    assert.equal(planned(changed, {verifyHistoricalProof: () => true}).works[0].action, "ai_rebuild");
  }
});
test("human legacy cannot become AI; attachment proof permits only immutable human copy", () => {
  const s = inventory({human: true});assert.equal(planned(s).rows[0].reason, "human_attachment_proof_required");
  s.humanAttachments = [proof(s, true)];
  assert.equal(planned(s).works.length, 0);
  assert.equal(planned(s, {verifyHumanAttachment: () => true}).works[0].action, "human_immutable_copy");
});
test("canonical legacy mirror is accepted without modern source keys; unpublished/foreign/forged is not", () => {
  const s = inventory();assert.equal(planned(s).works.length, 1);
  for (const extra of [{isDraft: true}, {isArchived: true}, {publicationState: "withdrawn"}, {contentLanguage: "en"}, {contentRevision: "cms-sha256-v1:" + "b".repeat(64)}]) {
    const changed = copy(s);Object.assign(changed.articles[0], extra);assert.equal(planned(changed).works.length, 0);
  }
});
test("duplicate episode IDs, source slugs/IDs and object paths are isolated; raw inventory survives", () => {
  const s = inventory({count: 3});s.catalog.episodes[1].id = s.catalog.episodes[0].id;
  const before = copy(s);const p = planned(s);assert.equal(p.inventory.raw, 3);assert.equal(p.inventory.uniqueIDs, 2);
  assert.equal(p.works.length, 1);assert.equal(p.works[0].source.articleId, s.articles[2].id);assert.deepEqual(s, before);
  s.articles.push(copy(s.articles[2]));assert.equal(planned(s).works.length, 0);
  const t = inventory();t.objects.push(copy(t.objects[0]));assert.equal(planned(t).works.length, 0);
});
test("exact storage bucket/path required; title/slug guessing and other hosts never authorize", () => {
  const s = inventory();
  for (const value of ["https://evil.invalid/old.m4a", url(s.objects[0].path).replace(bucket, "other.invalid"), "http://storage.googleapis.com/example.invalid/x"]) {
    s.catalog.episodes[0].audioURL = value;assert.equal(planned(s).rows[0].reason, "no_exact_object");
  }
});
test("plan validates complete bounded inputs and rejects unsafe limits", () => {
  assert.throws(() => planned({...inventory(), complete: false}));
  assert.throws(() => plan({snapshot: inventory(), policy: {...enabled, maxBatch: 26}}));
  assert.throws(() => planned({...inventory(), catalog: {episodes: Array(4097).fill({})}}));
});
test("actual legacy queue payload has exact four repair fields, deterministic ID and noNotify", async () => {
  const p = planned(inventory()), f = runtime();const work = p.works[0];
  const [a, b] = await Promise.all([f.store.admit(work), f.store.admit(work)]);
  assert.equal([a, b].filter(r => r.created).length, 1);assert.equal(f.documents.size, 1);
  const payload = f.job(work.key);assert.equal(payload.slug, "story-1");assert.notEqual(work.key, payload.slug);
  assert.equal(payload.noNotify, true);assert.deepEqual(payload.offlineRepair, {articleId: work.source.articleId,
    sourceContentRevision: work.source.sourceContentRevision, oldObjectPath: work.original.path, oldObjectGeneration: work.original.generation});
  assert.equal(payloadFor(work).offlineMaintenance.key, work.key);
});
test("finite admission cursor and render/character policy admit bounded work without skip", async () => {
  const p = planned(inventory({count: 6})), f = runtime();
  const policy = {...enabled, maxBatch: 2, maxAIRenders: 1};
  const first = await dispatchMaintenanceBatch({plan: p, policy, store: f.store});assert.equal(first.receipts.length, 2);assert.equal(first.cursor.offset, 2);
  assert.equal(first.budgetBlocked, 1);
  const second = await dispatchMaintenanceBatch({plan: p, cursor: first.cursor, policy, store: f.store});assert.equal(second.cursor.offset, 4);
  assert.equal(f.documents.size, 2);
  const blocked = await dispatchMaintenanceBatch({plan: p, cursor: second.cursor, policy: {...enabled, maxAICharacters: 1}, store: f.store});
  assert.equal(blocked.status, "complete");assert.equal(blocked.cursor.offset, 6);assert.equal(blocked.budgetBlocked, 2);
  await assert.rejects(dispatchMaintenanceBatch({plan: p, cursor: {fingerprint: "f".repeat(64), offset: 0}, policy, store: f.store}));
});
test("planner→admission→original legacy claim→repair→exact publication succeeds once", async () => {
  const s = inventory({count: 2}), f = runtime(s), p = planned(s), originalOther = copy(s.catalog.episodes[1]);
  await dispatchMaintenanceBatch({plan: p, policy: enabled, store: f.store});
  const key = p.works[0].key;const results = await Promise.all([f.run(key), f.run(key)]);
  assert.equal(results.filter(r => r.status === "done").length, 1);assert.deepEqual(f.calls, ["provider"]);
  assert.equal(f.job(key).status, "done");assert.equal(f.job(key).result, "published");
  assert.deepEqual(f.catalog().manifest.episodes[1], originalOther);assert.ok(f.objects.has(s.objects[0].path));
  await f.store.admit(p.works[0]);assert.equal((await f.run(key)).status, "skipped");assert.equal(f.calls.length, 1);
});
test("processing is not stolen after timeout; original claim cannot finish a replacement owner", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const claimed = await f.store.claim(work.key);assert.ok(claimed.claim);
  assert.equal(await f.store.claim(work.key), null);
  f.job(work.key).offlineRepairClaim = "other-owner";
  await assert.rejects(f.store.assertCurrent(work.key, claimed.claim), MaintenanceSuperseded);
  assert.equal(await f.store.finish(work.key, claimed.claim, "done", "published"), false);
  assert.equal(f.job(work.key).status, "processing");
});
test("source correction/removal or original object change prevents provider before starting", async () => {
  for (const mutation of [f => f.articles.set(article().id, article(1, "Correction")), f => f.articles.delete(article().id),
    f => {f.objects.values().next().value.generation = "999";}, f => {f.objects.values().next().value.metageneration = "2";}]) {
    const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);mutation(f);
    const result = await f.run(work.key);assert.ok(["superseded", "blocked"].includes(result.status));assert.deepEqual(f.calls, []);
    assert.equal(f.job(work.key).status, "error");
  }
});
test("source advance while provider awaits is guarded and does not adopt the new owner", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.adapters.generateAndPublishNarration = async ({assertCurrent}) => {
    f.calls.push("provider-start");f.articles.set(article().id, article(1, "New source"));await assertCurrent();assert.fail("stale commit");
  };
  assert.equal((await f.run(work.key)).status, "superseded");assert.deepEqual(f.calls, ["provider-start"]);
  assert.equal((await f.run(work.key)).status, "skipped");
});
test("unknown provider or publication outcome parks needs_readback and never paid-retries", async () => {
  for (const failReadback of [false, true]) {
    const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
    if (failReadback) f.adapters.readPublication = async () => {throw new Error("Readback transport lost");};
    else f.adapters.generateAndPublishNarration = async () => {f.calls.push("provider");throw new Error("Timed out after provider accepted");};
    assert.equal((await f.run(work.key)).status, "needs_readback");assert.equal(f.job(work.key).status, "error");
    await f.store.admit(work);assert.equal((await f.run(work.key)).status, "skipped");assert.equal(f.calls.filter(x => x === "provider").length, 1);
  }
});
test("a provider's published string alone cannot complete a job without source-bound readback", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.adapters.generateAndPublishNarration = async () => ({status: "published"});
  assert.equal((await f.run(work.key)).status, "needs_readback");assert.equal(f.job(work.key).result, "needs_readback");
});
test("changed original target rejects before provider; unrelated manifest additions remain allowed", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.catalog().manifest.episodes[0].audioURL = "changed";
  assert.equal((await f.run(work.key)).status, "superseded");assert.deepEqual(f.calls, []);
});
test("publish-only CAS replaces one row while preserving IDs, order, unknown keys and headers", async () => {
  const s = inventory({count: 3});s.objects.push(boundAI(s.articles[0]));
  const f = runtime(s), work = planned(s).works[0], before = copy(f.catalog());await f.store.admit(work);
  // An unrelated write after the plan must be merged from the fresh catalog, not dropped.
  f.catalog().manifest.episodes.push({id: "unrelated-new", retained: true});
  assert.equal((await f.run(work.key)).status, "done");assert.deepEqual(f.calls, ["commit"]);
  const after = f.catalog();assert.deepEqual(after.manifest.episodes.map(e => e.id), [...before.manifest.episodes.map(e => e.id), "unrelated-new"]);
  assert.deepEqual(after.manifest.episodes[1], before.manifest.episodes[1]);assert.deepEqual(after.manifest.episodes[0].arbitraryField, {preserve: 0});
  assert.deepEqual(after.metadata, before.metadata);assert.ok(f.objects.has(s.objects[0].path));
});
test("publication rejects changed candidate, old target, duplicate target, hold and CAS failure", async () => {
  for (const mode of ["candidate", "target", "duplicate", "hold", "CAS"]) {
    const s = inventory();s.objects.push(boundAI(s.articles[0]));const f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
    if (mode === "candidate") f.objects.get(work.candidate.path).metageneration = "2";
    if (mode === "target") f.catalog().manifest.episodes[0].title = "Changed";
    if (mode === "duplicate") f.catalog().manifest.episodes.push(copy(f.catalog().manifest.episodes[0]));
    if (mode === "hold") f.catalog().metadata.temporaryHold = true;
    if (mode === "CAS") f.adapters.commitCatalog = async () => {f.calls.push("CAS");throw new Error("412");};
    assert.notEqual((await f.run(work.key)).status, "done");assert.equal(f.job(work.key).status, "error");
    assert.equal(f.calls.includes("provider"), false);assert.equal((await f.run(work.key)).status, "skipped");
  }
});
test("verified AI reuse copies exact bytes to bound path and sidecar without provider", async () => {
  const s = inventory();s.historicalProofs = [proof(s)];const f = runtime(s), work = planned(s, {verifyHistoricalProof: () => true}).works[0];
  await f.store.admit(work);assert.equal((await f.run(work.key)).status, "done");
  assert.deepEqual(f.calls, ["read-bytes", "ai-copy", "sidecar", "commit"]);
  assert.ok(f.objects.has(work.original.path));assert.equal(f.catalog().manifest.episodes[0].id, work.targetID);
  assert.equal(validBinding([...f.objects.values()].find(o => o.path !== work.original.path), work.source), true);
});
test("human path uses actual helper, immutable upload and raw publisher; no TTS/deletion", async () => {
  const s = inventory({human: true});s.humanAttachments = [proof(s, true)];const f = runtime(s);
  const work = planned(s, {verifyHumanAttachment: () => true}).works[0];await f.store.admit(work);
  assert.equal((await f.run(work.key)).status, "done");assert.deepEqual(f.calls, ["read-bytes", "human-upload", "commit"]);
  assert.ok(f.objects.has(work.original.path));const row = f.catalog().manifest.episodes[0];
  assert.equal(row.kind, "human");assert.equal(row.id, work.targetID);assert.equal(row.sourceContentRevision, work.source.sourceContentRevision);
  const object = f.objects.get(pathFromURL(row.audioURL, bucket));assert.equal(object.metadata.podcastHosts, '["Actual human"]');
});
test("forged byte proof or revoked historical evidence does not copy or publish", async () => {
  for (const revoke of [false, true]) {
    const s = inventory({human: true});s.humanAttachments = [proof(s, true)];const f = runtime(s);
    const work = planned(s, {verifyHumanAttachment: () => true}).works[0];await f.store.admit(work);
    if (revoke) f.adapters.verifyEvidence = async () => false;
    else f.adapters.readAudio = async () => Buffer.from("other");
    assert.equal((await f.run(work.key)).status, "blocked");assert.equal(f.calls.includes("human-upload"), false);
  }
});
test("source change during human upload keeps original and prevents raw commit", async () => {
  const s = inventory({human: true});s.humanAttachments = [proof(s, true)];const f = runtime(s);
  const work = planned(s, {verifyHumanAttachment: () => true}).works[0];await f.store.admit(work);
  const upload = f.adapters.uploadHuman;f.adapters.uploadHuman = async (...args) => {await upload(...args);f.articles.set(article().id, article(1, "Correction"));};
  assert.equal((await f.run(work.key)).status, "superseded");assert.ok(f.objects.has(work.original.path));assert.equal(f.calls.includes("commit"), false);
});
test("queue identity mutation blocks old owner and does not overwrite forged replacement", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.job(work.key).offlineRepair.oldObjectGeneration = "999";
  await assert.rejects(f.store.claim(work.key));assert.equal(f.job(work.key).status, "pending");assert.deepEqual(f.calls, []);
});
test("gated CMS and schedule entrypoints use existing coalescing document and actual legacy jobs", async () => {
  const s = inventory(), f = runtime(s), entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration, loadSnapshot: async () => copy(s),
    store: f.store, adapters: f.adapters, bucket});
  await entry.onCanonicalCMSChange();await entry.onCanonicalCMSChange();
  assert.equal(f.documents.get("podcast_manifest_jobs/catalog").status, "pending");
  const result = await entry.reconcile();assert.equal(result.receipts.length, 1);assert.equal(f.job(result.receipts[0].key).status, "pending");
  const key = result.receipts[0].key;
  assert.deepEqual(await entry.onQueueCreated({data: {id: "normal", data: () => ({slug: "normal"})}}), {handled: false});
  assert.equal((await entry.onQueueCreated({data: {id: key, data: () => copy(f.job(key))}})).status, "done");
});
test("disabled recognized human event is handled and cannot fall through to legacy TTS", async () => {
  const f = runtime(), entry = createAutomaticOfflineEntrypoints({db: f.db, store: f.store});
  assert.deepEqual(await entry.onQueueCreated({data: {id: "human", data: () => ({offlineMaintenance: {}})}}), {handled: true, status: "disabled"});
});
test("stored cursor advances past terminal jobs without a new collection or state replacement", async () => {
  const s = inventory({count: 6}), f = runtime(s), policy = {...enabled, maxBatch: 2};
  const entry = createAutomaticOfflineEntrypoints({db: f.db, policy, qualifyNarration, loadSnapshot: async () => copy(s), store: f.store, adapters: f.adapters, bucket});
  const first = await entry.reconcile();assert.equal(first.cursorPersisted, true);assert.equal(first.cursor.offset, 2);
  for (const receipt of first.receipts) f.job(receipt.key).status = "error";
  const second = await entry.reconcile();assert.equal(second.cursor.offset, 4);assert.equal(second.receipts[0].created, true);
  const manifest = f.documents.get("podcast_manifest_jobs/catalog");assert.equal(manifest.schemaVersion, 1);assert.equal(manifest.status, "pending");
  assert.equal(manifest.offlineMaintenanceCursor.offset, 4);assert.equal(f.documents.size, 5);
});
test("scheduled recovery of a pending lost event uses same original claim and runs once", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration, loadSnapshot: async () => copy(s), store: f.store, adapters: f.adapters, bucket});
  const result = await entry.onScheduledInventory();assert.equal(result.recovery.status, "done");assert.deepEqual(f.calls, ["provider"]);
  const later = await entry.onScheduledInventory();assert.equal(later.recovery, null);assert.deepEqual(f.calls, ["provider"]);
});
test("schedule and created trigger race share one provider execution", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration, loadSnapshot: async () => copy(s), store: f.store, adapters: f.adapters, bucket});
  await Promise.all([entry.onScheduledInventory(), entry.onQueueCreated({data: {id: work.key, data: () => copy(f.job(work.key))}})]);
  assert.deepEqual(f.calls, ["provider"]);assert.equal(f.job(work.key).status, "done");
});
test("new CMS request during inventory prevents stale cursor write over newer request", async () => {
  const s = inventory(), f = runtime(s);let entry;
  entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration, loadSnapshot: async () => {await entry.onCanonicalCMSChange();return copy(s);},
    store: f.store, adapters: f.adapters, bucket});
  const result = await entry.reconcile();assert.equal(result.cursorPersisted, false);
  assert.equal(f.documents.get("podcast_manifest_jobs/catalog").offlineMaintenanceCursor, undefined);
});
test("zero AI budget still scans to and admits later publish-only work", async () => {
  const s = inventory({count: 2});s.objects.push(boundAI(s.articles[1]));const f = runtime(s), p = planned(s);
  const result = await dispatchMaintenanceBatch({plan: p, policy: {...enabled, maxAIRenders: 0, maxAICharacters: 0}, store: f.store});
  assert.equal(result.budgetBlocked, 1);assert.equal(result.cursor.offset, 2);assert.equal(f.documents.size, 1);
  assert.equal(f.job(p.works[1].key).offlineMaintenance.work.action, "publish_only");
});
test("revoked runtime policy inside an asynchronous provider step prevents commit", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);let active = true;
  f.adapters.assertRuntimePolicy = async () => {if (!active) throw new Error("runtime gate closed");};
  f.adapters.generateAndPublishNarration = async ({assertCurrent}) => {f.calls.push("provider");active = false;await assertCurrent();assert.fail("closed gate commit");};
  assert.equal((await f.run(work.key)).status, "needs_readback");assert.deepEqual(f.calls, ["provider"]);
});
test("repeated finite cycles eventually admit every AI item; duplicate jobs do not reserve budget again", async () => {
  const s = inventory({count: 6}), f = runtime(s), policy = {...enabled, maxBatch: 2, maxAIRenders: 1};
  const entry = createAutomaticOfflineEntrypoints({db: f.db, policy, qualifyNarration, loadSnapshot: async () => copy(s), store: f.store, adapters: f.adapters, bucket});
  const created = new Set();
  for (let i = 0; i < 9; i++) {
    const result = await entry.reconcile();assert.ok(result.reserved.renders <= 1);
    for (const receipt of result.receipts) if (receipt.created) {assert.equal(created.has(receipt.key), false);created.add(receipt.key);}
  }
  assert.equal(created.size, 6);assert.equal([...f.documents.keys()].filter(k => k.startsWith(COLLECTION + "/")).length, 6);
});
test("parallel duplicate admission never creates the same job or reserves its budget twice", async () => {
  const s = inventory(), f = runtime(s), p = planned(s), policy = {...enabled, maxAIRenders: 1};
  const results = await Promise.all(Array.from({length: 4}, () => dispatchMaintenanceBatch({plan: p, policy, store: f.store})));
  assert.equal(results.reduce((n, r) => n + r.reserved.renders, 0), 1);assert.equal(f.documents.size, 1);
});
test("actual Street Fighter canonical content qualifies without rewriting its original CMS revision", () => {
  const fs = require("node:fs"), source = JSON.parse(fs.readFileSync(require("node:path").join(__dirname,
    "../Docs/Integrations/OfflineStreetFighter-2026-11-01/normalized-mirror-source.json"), "utf8"));
  assert.equal(typeof source.fieldData.content, "string");assert.equal(source.fieldData["post-body"], undefined);
  const s = inventory(), original = copy(source);s.articles = [source];s.objects[0].path = `podcasts/narration/${source.fieldData.slug}/old.m4a`;
  Object.assign(s.catalog.episodes[0], {id: `ai-${source.fieldData.slug}`, articleSlug: source.fieldData.slug, audioURL: url(s.objects[0].path)});
  const work = planned(s).works[0];assert.equal(work.action, "ai_rebuild");assert.equal(work.source.sourceContentRevision, source.contentRevision);
  assert.ok(work.characters > source.fieldData.content.length);assert.deepEqual(source, original);
});
test("AI admission requires exact source-bound full script count; a body-only budget does not authorize", async () => {
  const s = inventory(), f = runtime(s), p = planned(s), work = p.works[0];
  assert.ok(work.characters > s.articles[0].fieldData.content.length);
  const r = await dispatchMaintenanceBatch({plan: p, policy: {...enabled, maxAICharacters: s.articles[0].fieldData.content.length}, store: f.store});
  assert.equal(r.budgetBlocked, 1);assert.equal(f.documents.size, 0);
  assert.equal(planned(s, {qualifyNarration: () => ({source: {wrong: "revision"}, fullText: "x".repeat(100)})}).works.length, 0);
  assert.equal(planned(s, {qualifyNarration: undefined}).rows[0].reason, "render_script_qualification_required");
});
test("changed rendered credits/recipe under the same article revision blocks provider", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.adapters.readNarrationScript = async () => ({source: work.source, fullText: qualifyNarration({article: s.articles[0], source: work.source}).fullText + "new credits"});
  assert.equal((await f.run(work.key)).status, "superseded");assert.deepEqual(f.calls, []);
});
test("publish-only/human acknowledgement without actual commit never completes", async () => {
  for (const human of [false, true]) {
    const s = inventory({human});if (human) s.humanAttachments = [proof(s, true)];else s.objects.push(boundAI(s.articles[0]));
    const f = runtime(s), work = planned(s, {verifyHumanAttachment: () => true}).works[0];await f.store.admit(work);
    f.adapters.commitCatalog = async () => ({published: true});
    assert.equal((await f.run(work.key)).status, "needs_readback");assert.equal(f.job(work.key).status, "error");
    assert.equal(f.catalog().manifest.episodes[0].sourceContentRevision, undefined);
  }
});
test("known pre-TTS quota deferral is time-gated and safely resumes; unknown exceptions still never retry", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const generate = f.adapters.generateAndPublishNarration;let preflights = 0;
  f.adapters.generateAndPublishNarration = async opts => ++preflights === 1 ? {status: "deferred_quota"} : generate(opts);
  assert.equal((await f.run(work.key)).status, "deferred_quota");assert.equal(f.job(work.key).status, "pending");
  assert.equal((await f.run(work.key)).status, "skipped");assert.equal(preflights, 1);assert.deepEqual(f.calls, []);
  f.advance(3600000);assert.equal((await f.run(work.key)).status, "done");assert.equal(preflights, 2);assert.deepEqual(f.calls, ["provider"]);
});
test("quota deferrals are finite and a late old owner cannot requeue a newer claim", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.adapters.generateAndPublishNarration = async () => ({status: "deferred_quota"});
  const run = () => runMaintenanceJob({key: work.key, policy: {...enabled, maxQuotaDeferrals: 1}, store: f.store, adapters: f.adapters, bucket});
  assert.equal((await run()).status, "deferred_quota");f.advance(3600000);
  assert.equal((await run()).status, "quota_deferral_limit");assert.equal(f.job(work.key).status, "error");
  assert.equal((await run()).status, "skipped");assert.deepEqual(f.calls, []);
});
test("canonical published timestamp must remain a string as in the actual source capture", () => {
  const a = article();a.lastPublished = 1;a.contentRevision = contentRevision(a);assert.throws(() => sourceOf(a));
});
test("normal human folder/row contract qualifies actual bytes without a new CMS field or word-for-word proof", () => {
  const s = inventory({human: true}), bytes = Buffer.from([0, 0, 0, 20, ...Buffer.from("ftypM4A human recording")]);s.objects[0].size = bytes.length;
  const p = qualifyPublishedHumanAttachment({snapshot: s, episodeID: s.catalog.episodes[0].id, bytes});
  assert.equal(p.authority, "published-human-storage-v1");assert.equal(p.audioSHA256, digest(bytes));
  assert.equal(p.articleId, s.articles[0].id);assert.equal(p.sourceContentRevision, s.articles[0].contentRevision);
  assert.equal(p.objectGeneration, s.objects[0].generation);assert.equal(p.container, "m4a");
  const duplicate = copy(s);duplicate.catalog.episodes.push(copy(s.catalog.episodes[0]));
  assert.throws(() => qualifyPublishedHumanAttachment({snapshot: duplicate, episodeID: p.episodeID || s.catalog.episodes[0].id, bytes}));
  assert.throws(() => qualifyPublishedHumanAttachment({snapshot: s, episodeID: s.catalog.episodes[0].id, bytes: Buffer.from("not M4A")}));
});
test("new source repair passes verified OLD binding separately and retains original immutable audio", async () => {
  const s = inventory(), previous = copy(s.articles[0]), old = boundAI(previous);s.objects = [old];s.catalog.episodes[0].audioURL = url(old.path);
  s.articles[0] = article(1, "New canonical body");const f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const generate = f.adapters.generateAndPublishNarration;
  f.adapters.generateAndPublishNarration = async options => {
    assert.equal(options.oldSource.sourceContentRevision, previous.contentRevision);
    assert.notEqual(options.oldSource.sourceContentRevision, work.source.sourceContentRevision);return generate(options);
  };
  assert.equal((await f.run(work.key)).status, "done");assert.ok(f.objects.has(old.path));
});
test("actual repeated-hyphen CMS slugs preserve exact source/object folder and compact only legacy ID", () => {
  for (const slug of ["farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse", "copenhell---den-store-apropos-guide"]) {
    const s = inventory();s.articles[0].fieldData.slug = slug;s.articles[0].contentRevision = contentRevision(s.articles[0]);
    s.objects[0].path = `podcasts/narration/${slug}/old.m4a`;
    Object.assign(s.catalog.episodes[0], {id: `ai-${slug.replace(/-+/g, "-")}`, articleSlug: slug, audioURL: url(s.objects[0].path)});
    const work = planned(s).works[0];assert.equal(work.action, "ai_rebuild");assert.equal(work.source.articleSlug, slug);
    assert.equal(work.original.path, s.objects[0].path);assert.equal(payloadFor(work).slug, slug);
  }
});
test("repeated-hyphen acceptance does not admit traversal, delimiters, leading/trailing hyphens or oversized slugs", () => {
  for (const slug of ["../story", "story/../escape", "story%2fescape", "story\\escape", "story?x", "story#x", "-story", "story-", "story--", "a".repeat(241), "story\nother"]) {
    const a = article();a.fieldData.slug = slug;a.contentRevision = contentRevision(a);assert.throws(() => sourceOf(a));
  }
});
function withoutAudio(count = 1) {const s = inventory({count});s.catalog.episodes = [];s.objects = [];return s;}
test("all canonical articles are considered, including a missed normal creation without a catalog row", () => {
  const s = withoutAudio(3), p = planned(s);assert.equal(p.inventory.raw, 0);assert.equal(p.inventory.canonical, 3);assert.equal(p.inventory.missingRows, 3);
  assert.equal(p.works.length, 3);
  for (const work of p.works) {assert.equal(work.action, "ai_create");assert.equal(work.original, null);assert.equal(work.targetHash, null);
    assert.equal(payloadFor(work).offlineRepair, undefined);assert.equal(work.vacancy.completeQueueInventory, true);assert.ok(work.renderBudget.characters > 50);}
});
test("genuinely missed creation uses existing queue and immutable renderer callback to CAS append once", async () => {
  const s = inventory({count: 3}), original = copy(s.catalog.episodes.slice(1));s.catalog.episodes.shift();s.objects.shift();
  const f = runtime(s), work = planned(s).works.find(w => w.action === "ai_create");await f.store.admit(work);
  assert.equal((await f.run(work.key)).status, "done");assert.deepEqual(f.calls, ["provider", "commit"]);
  assert.deepEqual(f.catalog().manifest.episodes.slice(0, 2), original);const created = f.catalog().manifest.episodes[2];
  assert.equal(created.id, work.targetID);assert.equal(created.articleId, work.source.articleId);assert.equal(created.title, s.articles[0].fieldData.name);
  assert.equal(created.sourceContentRevision, work.source.sourceContentRevision);assert.equal((await f.run(work.key)).status, "skipped");
});
test("incomplete queue inventory and unknown previous normal jobs cannot authorize another paid create", () => {
  const s = withoutAudio();s.queueInventoryComplete = false;assert.equal(planned(s).rows[0].reason, "complete_audio_queue_inventory_required");
  s.queueInventoryComplete = true;
  for (const status of ["pending", "processing", "done", "error", "deferred_quota"]) {
    s.audioJobs = [{articleId: s.articles[0].id, status}];assert.equal(planned(s).rows[0].reason, "existing_audio_job_requires_readback");
  }
  for (const status of ["no_article", "empty", "deferred_quota"]) {
    s.audioJobs = [{articleId: s.articles[0].id, status, result: status}];assert.equal(planned(s).works[0].action, "ai_create");
  }
});
test("unpublished human, AI or orphan sidecar presence blocks new synthesis when no row exists", () => {
  for (const prefix of ["podcasts/articles/story-1/recording.m4a", "podcasts/narration/story-1/old.m4a", "podcasts/narration/story-1/orphan.m4a.json"]) {
    const s = withoutAudio();s.objects.push({path: prefix});assert.equal(planned(s).rows[0].reason, "unpublished_audio_requires_readback");
  }
});
test("legacy target-ID collision from distinct repeated-hyphen slugs fails closed", () => {
  const s = withoutAudio(2);s.articles[0].fieldData.slug = "story---shared";s.articles[1].fieldData.slug = "story-shared";
  for (const a of s.articles) a.contentRevision = contentRevision(a);
  assert.equal(planned(s).works.length, 0);assert.ok(planned(s).rows.every(r => r.reason === "ambiguous_new_episode_id"));
});
test("human/object/job arrival after the vacancy snapshot blocks create before provider", async () => {
  for (const mutation of [f => f.objects.set("podcasts/articles/story-1/new.m4a", {path: "podcasts/articles/story-1/new.m4a"}),
    f => f.catalog().manifest.episodes.push({id: "other-id", articleSlug: "story-1"}),
    f => f.documents.set(`${COLLECTION}/story-1`, {slug: "story-1", articleId: article().id, status: "pending"})]) {
    const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);mutation(f);
    assert.equal((await f.run(work.key)).status, "superseded");assert.deepEqual(f.calls, []);
  }
});
test("a competing human recording arriving during create prevents append and is never replaced with AI", async () => {
  const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const noAudio = f.adapters.assertNoAudio;
  f.adapters.assertNoAudio = async (actualWork, options) => {
    if (options.allowImmutablePath) f.objects.set("podcasts/articles/story-1/human.m4a", {path: "podcasts/articles/story-1/human.m4a"});
    return noAudio(actualWork, options);
  };
  assert.equal((await f.run(work.key)).status, "superseded");assert.deepEqual(f.calls, ["provider"]);
  assert.equal(f.catalog().manifest.episodes.length, 0);assert.equal((await f.run(work.key)).status, "skipped");
});
test("unknown create outcome remains same deterministic terminal job; no reset or paid retry", async () => {
  const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  f.adapters.generateAndPublishNarration = async () => {f.calls.push("provider");throw new Error("outcome unknown");};
  assert.equal((await f.run(work.key)).status, "needs_readback");
  const next = planned(copy(s)).works[0];assert.equal(next.key, work.key);await f.store.admit(next);
  assert.equal((await f.run(next.key)).status, "skipped");assert.deepEqual(f.calls, ["provider"]);
});
test("missing-row creation remains bounded across duplicate finite cycles", async () => {
  const s = withoutAudio(7), f = runtime(s), p = planned(s), policy = {...enabled, maxBatch: 3, maxAIRenders: 1};
  let cursor;const created = new Set();
  for (let n = 0; n < 9; n++) {
    if (cursor?.offset === p.works.length) cursor = undefined;
    const r = await dispatchMaintenanceBatch({plan: p, cursor, policy, store: f.store});cursor = r.cursor;assert.ok(r.reserved.renders <= 1);
    for (const receipt of r.receipts) if (receipt.created) created.add(receipt.key);
  }
  assert.equal(created.size, 7);
});
test("two append workers cannot duplicate or overwrite the same target", async () => {
  const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const results = await Promise.all([f.run(work.key), f.run(work.key)]);
  assert.equal(results.filter(r => r.status === "done").length, 1);assert.equal(f.catalog().manifest.episodes.length, 1);
  assert.equal(f.calls.filter(c => c === "provider").length, 1);
});
function currentInventory(f, original) {
  return {...copy(original), catalog: copy(f.catalog().manifest), objects: [...f.objects.values()].map(copy),
    audioJobs: [...f.documents.entries()].filter(([path]) => path.startsWith(COLLECTION + "/"))
      .map(([path, data]) => ({id: path.slice(COLLECTION.length + 1), data: copy(data)}))};
}
test("ai_create lost event recovers using the actual same pending job in the next full queue snapshot", async () => {
  const s = withoutAudio(), f = runtime(s), entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration,
    loadSnapshot: async () => currentInventory(f, s), store: f.store, adapters: f.adapters, bucket});
  const first = await entry.reconcile();assert.equal(first.receipts.length, 1);assert.equal(first.receipts[0].created, true);
  const second = await entry.onScheduledInventory();assert.equal(second.receipts[0].created, false);assert.equal(second.recovery.status, "done");
  assert.deepEqual(f.calls, ["provider", "commit"]);assert.equal((await entry.onScheduledInventory()).recovery, null);
});
test("ai_create quota pending plus exact canonical reservation remains discoverable and resumes only after cooldown", async () => {
  const s = withoutAudio(), f = runtime(s), entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration,
    loadSnapshot: async () => currentInventory(f, s), store: f.store, adapters: f.adapters, bucket});
  const generate = f.adapters.generateAndPublishNarration;let preflights = 0;
  f.adapters.generateAndPublishNarration = async options => {
    f.documents.set(`${COLLECTION}/${options.slug}`, {slug: options.slug, articleId: options.articleId, status: "offline_reserved", offlineMaintenanceReservation: options.maintenanceWork.key});
    return ++preflights === 1 ? {status: "deferred_quota"} : generate(options);
  };
  assert.equal((await entry.onScheduledInventory()).recovery.status, "deferred_quota");
  assert.equal((await entry.onScheduledInventory()).recovery, null);assert.equal(preflights, 1);
  f.advance(3600000);assert.equal((await entry.onScheduledInventory()).recovery.status, "done");assert.equal(preflights, 2);
  assert.deepEqual(f.calls, ["provider", "commit"]);
});
test("only exact physical job plus immutable work permits own reservation; copied markers and altered work block", async () => {
  const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);
  const reservation = {id: work.source.articleSlug, data: {slug: work.source.articleSlug, articleId: work.source.articleId,
    status: "offline_reserved", offlineMaintenanceReservation: work.key}};
  const snapshot = currentInventory(f, s);snapshot.audioJobs.push(reservation);
  assert.equal(planned(snapshot).works[0].key, work.key);
  for (const mutate of [x => {x.audioJobs[0].id = "copied-physical-key";}, x => {x.audioJobs[0].data.offlineMaintenance.work.characters++;},
    x => {x.audioJobs = [x.audioJobs[1]];}, x => {x.audioJobs[1].data.offlineMaintenanceReservation = "another-owner";}]) {
    const bad = copy(snapshot);mutate(bad);assert.equal(planned(bad).rows[0].reason, "existing_audio_job_requires_readback");
  }
});
test("same-work processing/error can be inventoried without executing or resetting them", async () => {
  for (const status of ["processing", "error"]) {
    const s = withoutAudio(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);f.job(work.key).status = status;
    const entry = createAutomaticOfflineEntrypoints({db: f.db, policy: enabled, qualifyNarration,
      loadSnapshot: async () => currentInventory(f, s), store: f.store, adapters: f.adapters, bucket});
    const result = await entry.onScheduledInventory();assert.equal(result.plan.works[0].key, work.key);assert.equal(result.recovery, null);
    assert.equal(f.job(work.key).status, status);assert.deepEqual(f.calls, []);
  }
});
test("current numeric runtime budget is checked after admission before any provider effect", async () => {
  for (const lowered of [{...enabled, maxAIRenders: 0}, {...enabled, maxAICharacters: 1}]) {
    const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);let currentPolicy = lowered;
    f.adapters.readRuntimePolicy = async () => currentPolicy;
    assert.equal((await f.run(work.key)).status, "budget_blocked");assert.equal(f.job(work.key).status, "pending");assert.deepEqual(f.calls, []);
    currentPolicy = enabled;assert.equal((await f.run(work.key)).status, "done");
  }
});
test("numeric policy lowered during the asynchronous producer guard prevents later paid work/commit", async () => {
  const s = inventory(), f = runtime(s), work = planned(s).works[0];await f.store.admit(work);let currentPolicy = enabled;
  f.adapters.readRuntimePolicy = async () => currentPolicy;
  f.adapters.generateAndPublishNarration = async ({assertCurrent}) => {
    f.calls.push("producer-preflight");currentPolicy = {...enabled, maxAIRenders: 0};await assertCurrent();assert.fail("forbidden TTS");
  };
  assert.equal((await f.run(work.key)).status, "needs_readback");assert.deepEqual(f.calls, ["producer-preflight"]);
});
test("actual renderer metadata replaces target duration/credits/title/art and preserves existing GUID/extensions/unrelated rows", async () => {
  const s = inventory({count: 2});s.catalog.episodes[0].guid = "stable-guid";s.catalog.episodes[0].durationSeconds = 15;
  const candidate = boundAI(s.articles[0]);s.objects.push(candidate);const f = runtime(s), work = planned(s).works[0], before = copy(f.catalog());
  const fields = {id: work.targetID, articleId: work.source.articleId, articleSlug: work.source.articleSlug,
    sourceContentRevision: work.source.sourceContentRevision, kind: "ai", audioURL: url(candidate.path), audioBytes: candidate.size,
    title: "Actual rendered title", subtitle: "Lyt til artiklen", hosts: ["Actual narrator"], durationSeconds: 123.4,
    publishedAt: "2026-11-01T09:00:00Z", guid: "stable-guid", imageURL: "https://example.invalid/real-cover.jpg", description: "Actual rendered description"};
  await publishRawReplacement({work, bucket, replacement: {path: candidate.path, audioURL: url(candidate.path), episode: fields}, assertCurrent: async () => {}, ...f.adapters});
  const target = f.catalog().manifest.episodes[0];assert.equal(target.durationSeconds, 123);assert.deepEqual(target.hosts, ["Actual narrator"]);
  assert.equal(target.title, fields.title);assert.equal(target.imageURL, fields.imageURL);assert.equal(target.guid, "stable-guid");
  assert.deepEqual(target.arbitraryField, before.manifest.episodes[0].arbitraryField);assert.deepEqual(f.catalog().manifest.episodes[1], before.manifest.episodes[1]);
});
test("renderer metadata cannot forge source/audio identity, replace GUID or publish malformed known fields", async () => {
  for (const fields of [{articleId: "f".repeat(24)}, {audioURL: "https://wrong.invalid/audio"}, {audioBytes: 999}, {kind: "human"},
    {guid: "changed"}, {hosts: []}, {durationSeconds: -1}, {publishedAt: "bad"}, {imageURL: "http://unsafe.invalid/a"}, {unknownField: "write"}]) {
    const s = inventory();s.catalog.episodes[0].guid = "original";const candidate = boundAI(s.articles[0]);s.objects.push(candidate);
    const f = runtime(s), work = planned(s).works[0];
    await assert.rejects(publishRawReplacement({work, bucket, replacement: {path: candidate.path, audioURL: url(candidate.path), episode: fields}, assertCurrent: async () => {}, ...f.adapters}));
    assert.deepEqual(f.calls, []);assert.equal(f.catalog().manifest.episodes[0].guid, "original");
  }
});
const budgetPath = "podcast_manifest_jobs/catalog";
const aggregateBudget = f => f.documents.get(budgetPath)?.offlineMaintenanceBudget;
test("global AI character reservation and new queue creation are atomic under competing work", async () => {
  const s = inventory({count: 2}), works = planned(s).works, f = memoryDB(), cap = works[0].characters + works[1].characters - 1;
  f.documents.set(budgetPath, {schemaVersion: 1, status: "pending", requestedToken: "original-request", unknown: {preserve: true}});
  const store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: cap});
  const results = await Promise.all(works.map(w => store.admit(w)));
  assert.equal(results.filter(r => r.created).length, 1);assert.equal(results.filter(r => r.status === "budget_blocked").length, 1);
  assert.equal(aggregateBudget(f).characters, works[0].characters);assert.ok(aggregateBudget(f).characters <= cap);
  const job = f.documents.get(`${COLLECTION}/${works[0].key}`);
  assert.deepEqual(job.offlineAICharacterReservation, {version: 1, budgetID: "automatic-offline-v1", characters: works[0].characters});
  assert.equal(f.documents.get(budgetPath).requestedToken, "original-request");assert.deepEqual(f.documents.get(budgetPath).unknown, {preserve: true});
});
test("aggregate reservation persists across recreated store/process and duplicate deliveries", async () => {
  const works = planned(inventory({count: 2})).works, f = memoryDB(), cap = works[0].characters;
  const first = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: cap});await first.admit(works[0]);
  const second = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: cap});
  const duplicate = await second.admit(works[0]);assert.equal(duplicate.created, false);
  assert.equal((await second.admit(works[1])).status, "budget_blocked");assert.equal(aggregateBudget(f).characters, cap);
  assert.equal([...f.documents.keys()].filter(k => k.startsWith(COLLECTION + "/")).length, 1);
});
test("pending, quota deferral, done and unknown outcomes neither refund nor double-reserve characters", async () => {
  const work = planned(inventory()).works[0], f = memoryDB();let clock = 1000;
  const store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: work.characters, now: () => clock});await store.admit(work);
  await store.admit(work);assert.equal(aggregateBudget(f).characters, work.characters);
  const first = await store.claim(work.key);await store.deferQuota(work.key, first.claim, {quotaRetryMs: 60000, maxQuotaDeferrals: 2});
  await store.admit(work);assert.equal(aggregateBudget(f).characters, work.characters);
  clock += 60000;const second = await store.claim(work.key);await store.finish(work.key, second.claim, "error", "needs_readback");
  await store.admit(work);assert.equal(aggregateBudget(f).characters, work.characters);assert.equal(await store.claim(work.key), null);
  // A different done result likewise cannot refund an already reserved source.
  f.documents.get(`${COLLECTION}/${work.key}`).status = "done";await store.admit(work);assert.equal(aggregateBudget(f).characters, work.characters);
});
test("zero aggregate cap denies new TTS but permits human and verified/publish-only immutable copies", async () => {
  const ai = planned(inventory()).works[0], humanSnapshot = inventory({human: true});humanSnapshot.humanAttachments = [proof(humanSnapshot, true)];
  const human = planned(humanSnapshot, {verifyHumanAttachment: () => true}).works[0];
  const copySnapshot = inventory();copySnapshot.historicalProofs = [proof(copySnapshot)];
  const reuse = planned(copySnapshot, {verifyHistoricalProof: () => true}).works[0];
  const publishSnapshot = inventory();publishSnapshot.objects.push(boundAI(publishSnapshot.articles[0]));const publish = planned(publishSnapshot).works[0];
  const f = memoryDB(), store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: 0});
  assert.equal((await store.admit(ai)).status, "budget_blocked");assert.equal(f.documents.has(`${COLLECTION}/${ai.key}`), false);
  for (const work of [human, reuse, publish]) {
    assert.equal((await store.admit(work)).created, true);assert.equal(f.documents.get(`${COLLECTION}/${work.key}`).offlineAICharacterReservation, undefined);
  }
  assert.equal(aggregateBudget(f), undefined);
});
test("global aggregate cap covers newly created missing-row AI as well as existing-row repair", async () => {
  const work = planned(withoutAudio()).works[0], f = memoryDB(), store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: work.characters - 1});
  assert.equal((await store.admit(work)).status, "budget_blocked");assert.equal(f.documents.size, 0);
});
test("unknown/malformed global budget is never reset or overwritten to admit a new AI job", async () => {
  const work = planned(inventory()).works[0];
  for (const budget of [null, [], {}, {version: 2, budgetID: "automatic-offline-v1", characters: 0},
    {version: 1, budgetID: "other-budget", characters: 0}, {version: 1, budgetID: "automatic-offline-v1", characters: -1},
    {version: 1, budgetID: "automatic-offline-v1", characters: NaN}, {version: 1, budgetID: "automatic-offline-v1", characters: 1.5},
    {version: 1, budgetID: "automatic-offline-v1", characters: 0, unexpected: "field"}]) {
    const f = memoryDB(), before = {status: "processing", requestedToken: "keep", offlineMaintenanceBudget: budget};f.documents.set(budgetPath, copy(before));
    const store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: 100000});
    assert.equal((await store.admit(work)).status, "budget_invalid");assert.deepEqual(f.documents.get(budgetPath), before);assert.equal(f.documents.size, 1);
  }
});
test("aggregate cap accepts only a finite nonnegative safe integer up to ten million", () => {
  for (const limit of [-1, 1.5, NaN, Infinity, "1000", null, 10000001, Number.MAX_SAFE_INTEGER]) {
    assert.throws(() => createLegacyMaintenanceStore({db: {}, aggregateCharacterLimit: limit}), /aggregate/);
  }
  assert.doesNotThrow(() => createLegacyMaintenanceStore({db: memoryDB().db, aggregateCharacterLimit: 10000000}));
});
test("cap-enabled worker cannot claim an unreserved or altered AI job", async () => {
  const work = planned(inventory()).works[0], f = memoryDB(), unboundedLocal = createLegacyMaintenanceStore({db: f.db});
  await unboundedLocal.admit(work);
  const bounded = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: 0});
  await assert.rejects(bounded.claim(work.key), /reservation/);assert.equal(f.documents.get(`${COLLECTION}/${work.key}`).status, "pending");
  const other = memoryDB(), reservedStore = createLegacyMaintenanceStore({db: other.db, aggregateCharacterLimit: work.characters});await reservedStore.admit(work);
  other.documents.get(`${COLLECTION}/${work.key}`).offlineAICharacterReservation.characters--;
  await assert.rejects(reservedStore.claim(work.key), /reservation/);assert.equal(aggregateBudget(other).characters, work.characters);
});
test("an existing unknown aggregate counter blocks continued original-claim authority without paid retry", async () => {
  const work = planned(inventory()).works[0], f = memoryDB(), store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: work.characters});
  await store.admit(work);const claim = await store.claim(work.key);f.documents.get(budgetPath).offlineMaintenanceBudget = {unknown: true};
  await assert.rejects(store.assertCurrent(work.key, claim.claim), MaintenanceSuperseded);
  assert.equal((await store.admit(work)).created, false);assert.deepEqual(f.documents.get(budgetPath).offlineMaintenanceBudget, {unknown: true});
});
test("existing manifest request/claim/finish preserves cumulative aggregate budget and unrelated fields", async () => {
  const work = planned(inventory()).works[0], f = memoryDB();f.documents.set(budgetPath, {unrelated: "keep"});
  const store = createLegacyMaintenanceStore({db: f.db, aggregateCharacterLimit: work.characters});await store.admit(work);
  const manifest = createManifestJobStore({db: f.db, now: () => 1000});await manifest.request();
  const claim = await manifest.claim();assert.ok(claim);await manifest.assertCurrent(claim.leaseToken);await manifest.finish(claim.leaseToken, true);
  assert.deepEqual(aggregateBudget(f), {version: 1, budgetID: "automatic-offline-v1", characters: work.characters});
  assert.equal(f.documents.get(budgetPath).unrelated, "keep");assert.equal(f.documents.get(budgetPath).status, "done");
});
