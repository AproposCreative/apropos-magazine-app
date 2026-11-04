const {test} = require("node:test");
const assert = require("node:assert/strict");
const {fetchLiveCatalog, synchronizeLiveCatalog, firestoreCatalogStore,
  catalogEventAction, synchronizeCatalogEvent, isVisibleMirrorItem} = require("./webflowCatalog");

const collectionId = "a".repeat(24);
const id = (number) => number.toString(16).padStart(24, "0");
const item = (number, extra = {}) => ({id: id(number), fieldData: {name: "Published", slug: `story-${number}`},
  isDraft: false, isArchived: false, lastPublished: "2026-10-20T10:00:00Z", ...extra});
const envelope = (items, total = items.length, offset = 0, limit = 100) =>
  ({items, pagination: {total, offset, limit}});
const response = (payload, status = 200) => ({ok: status === 200, status, json: async () => payload});

// Runs the actual Firestore adapter against an atomic in-memory transaction
// implementation. No SDK import, Firebase initialization, emulator or network.
function database(now = () => 1000) {
  const documents = new Map();
  const commits = [];
  const collectionReads = [];
  const ref = (path) => ({path});
  const db = {
    collection: (name) => ({
      doc: (key) => ref(`${name}/${key}`),
      get: async () => {collectionReads.push(name); return {docs: [...documents.entries()]
        .filter(([key]) => key.startsWith(name + "/"))
        .map(([path, value]) => ({id: path.split("/")[1], data: () => structuredClone(value)}))};},
    }),
    runTransaction: async (callback) => {
      const pending = [];
      const result = await callback({
        get: async ({path}) => ({data: () => structuredClone(documents.get(path))}),
        set: ({path}, value) => pending.push([path, structuredClone(value)]),
        delete: ({path}) => pending.push([path, undefined]),
      });
      for (const [path, value] of pending) {
        if (value === undefined) documents.delete(path);
        else documents.set(path, value);
      }
      commits.push(pending);
      return result;
    },
  };
  const atomic = db.runTransaction;
  let tail = Promise.resolve();
  db.runTransaction = (callback) => {
    const result = tail.then(() => atomic(callback));
    tail = result.catch(() => {});
    return result;
  };
  return {documents, commits, collectionReads, store: firestoreCatalogStore({db, collection: "articles", collectionId,
    timestamp: () => "injected-server-timestamp", now})};
}

test("uses live endpoint and raw pagination even if archived items are filtered", async () => {
  const requests = [];
  const rows = [item(1, {isArchived: true}), item(2), item(3)];
  const result = await fetchLiveCatalog({collectionId, apiKey: "local-fixture", limit: 2,
    transport: async (url, options) => {
      const parsed = new URL(url);
      assert.equal(parsed.pathname, `/v2/collections/${collectionId}/items/live`);
      assert.equal(parsed.searchParams.has("live"), false);
      assert.equal(options.headers.Authorization, "Bearer local-fixture");
      const offset = Number(parsed.searchParams.get("offset"));
      requests.push(offset);
      return response(envelope(rows.slice(offset, offset + 2), 3, offset, 2));
    }});
  assert.deepEqual(requests, [0, 2]);
  assert.deepEqual(result.map((row) => row.id), [id(2), id(3)]);
});

test("uses server total on a short page and does not request an extra empty page", async () => {
  const offsets = [];
  const result = await fetchLiveCatalog({collectionId, apiKey: "local-fixture", transport: async (url) => {
    const offset = Number(new URL(url).searchParams.get("offset"));
    offsets.push(offset);
    return response(envelope([item(offset + 1)], 2, offset));
  }});
  assert.deepEqual(offsets, [0, 1]);
  assert.equal(result.length, 2);
});

test("live endpoint fieldData remains visible when staged edits are in draft", async () => {
  const result = await fetchLiveCatalog({collectionId, apiKey: "local-fixture",
    transport: async () => response(envelope([item(1, {isDraft: true})]))});
  assert.equal(result[0].isDraft, false);
});

test("rejects malformed, truncated or excessive envelopes rather than an empty success", async () => {
  for (const payload of [{}, {items: []}, envelope([], 1), envelope([item(1)], 0),
    envelope([item(1)], 10001), envelope([item(1)], 1, 10),
    envelope([item(1, {fieldData: null})]), envelope([item(1, {lastPublished: null})]),
    envelope([item(1, {id: "../outside"})])]) {
    await assert.rejects(fetchLiveCatalog({collectionId, apiKey: "local-fixture",
      transport: async () => response(payload)}));
  }
});

test("rejects duplicate IDs, locale collisions and changing totals during pagination", async () => {
  for (const second of [envelope([item(1)], 2, 1), envelope([item(2)], 3, 1)]) {
    let request = 0;
    await assert.rejects(fetchLiveCatalog({collectionId, apiKey: "local-fixture",
      transport: async () => response(request++ ? second : envelope([item(1)], 2))}));
  }
});

test("non-success HTTP and scan deadline are errors without leaked server bodies", async () => {
  await assert.rejects(fetchLiveCatalog({collectionId, apiKey: "local-fixture",
    transport: async () => response({secret: "not-for-logs"}, 429)}), /HTTP 429/);
  let time = 10;
  await assert.rejects(fetchLiveCatalog({collectionId, apiKey: "local-fixture", now: () => time,
    deadline: 15, transport: async () => {time = 16; return response(envelope([]));}}), /deadline/);
});

test("successful full sync replaces removed fields and withdraws only proven-owned absent rows", async () => {
  const fixture = database();
  fixture.documents.set(`articles/${id(1)}`, {id: id(1), fieldData: {removed: "old content"}});
  fixture.documents.set(`articles/${id(2)}`, {id: id(2), source: "webflow", sourceCollectionId: collectionId,
    fieldData: {slug: "withdrawn", content: "must disappear"}});
  fixture.documents.set(`articles/${id(3)}`, {id: id(3), fieldData: {slug: "legacy-needs-inventory"}});
  fixture.documents.set(`articles/${id(4)}`, {id: id(4), source: "webflow", sourceCollectionId: "b".repeat(24)});
  const result = await synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async (url) => url.includes(`/items/${id(2)}/live`) ? response({}, 404) : response(envelope([item(1)]))});
  assert.equal(result.withdrawn, 1);
  assert.equal(fixture.documents.get(`articles/${id(1)}`).fieldData.removed, undefined);
  const withdrawn = fixture.documents.get(`articles/${id(2)}`);
  assert.equal(withdrawn.isDraft, true);
  assert.equal(withdrawn.lastPublished, null);
  assert.equal(withdrawn.fieldData.content, undefined);
  assert.equal(fixture.documents.get(`articles/${id(3)}`).publicationState, undefined);
  assert.equal(fixture.documents.get(`articles/${id(4)}`).publicationState, undefined);
  assert.equal(fixture.documents.has("cms_sync_leases/articles"), false);
});

test("failed second page does not mutate articles or withdraw anything", async () => {
  const fixture = database();
  fixture.documents.set(`articles/${id(9)}`, {source: "webflow", sourceCollectionId: collectionId});
  const before = structuredClone(fixture.documents);
  let request = 0;
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async () => request++ ? response({}, 503) : response(envelope([item(1)], 2))}));
  assert.deepEqual(fixture.documents, before);
});

test("active lease rejects overlapping sync before fetching", async () => {
  const fixture = database();
  await fixture.store.acquire("first", 2000);
  let fetched = false;
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async () => {fetched = true;}}), /already running/);
  assert.equal(fetched, false);
  assert.equal(fixture.documents.get("cms_sync_leases/articles").owner, "first");
});

test("expired owner cannot commit or release a replacement lease", async () => {
  let time = 1000;
  const fixture = database(() => time);
  await fixture.store.acquire("old", 1100);
  time = 1200;
  await fixture.store.acquire("new", 2000);
  await assert.rejects(fixture.store.commit("old", [{id: id(1), value: item(1)}]), /lease lost/);
  await fixture.store.release("old");
  assert.equal(fixture.documents.get("cms_sync_leases/articles").owner, "new");
  assert.equal(fixture.documents.has(`articles/${id(1)}`), false);
});

test("lease expiry during a scan prevents both publication and withdrawal writes", async () => {
  let time = 1000;
  const fixture = database(() => time);
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    leaseMs: 50, now: () => time, transport: async () => {
      time = 1100; return response(envelope([item(1)]));
    }}), /lease lost/);
  assert.equal(fixture.documents.size, 0);
});

test("failure of a later atomic chunk is repaired by a retry without stale CMS fields", async () => {
  const fixture = database();
  const transport = async (url) => {
    const offset = Number(new URL(url).searchParams.get("offset"));
    return response(envelope(Array.from({length: offset ? 1 : 100}, (_, index) => item(offset + index + 1)), 101, offset));
  };
  const original = fixture.store.commit;
  let calls = 0;
  fixture.store.commit = async (...args) => {if (++calls === 2) throw new Error("write failed"); return original(...args);};
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    transport, now: () => 1000}), /write failed/);
  assert.equal([...fixture.documents.keys()].filter((key) => key.startsWith("articles/")).length, 100);
  fixture.store.commit = original;
  await synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture", transport, now: () => 1000});
  assert.equal([...fixture.documents.keys()].filter((key) => key.startsWith("articles/")).length, 101);
});

test("only publication events can request an alert; withdrawal and updates refresh silently", () => {
  assert.equal(catalogEventAction("collection_item_published"), "publish");
  for (const event of ["collection_item_unpublished", "collection_item_deleted", "collection_item_changed"]) {
    assert.equal(catalogEventAction(event), "refresh");
  }
  assert.equal(catalogEventAction("unknown"), "ignore");
});

test("individual live confirmation recovers a page-shift omission without withdrawing it", async () => {
  const fixture = database();
  fixture.documents.set(`articles/${id(2)}`, {source: "webflow", sourceCollectionId: collectionId});
  const result = await synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async (url) => response(url.includes(`/items/${id(2)}/live`) ? item(2) : envelope([item(1)]))});
  assert.equal(result.withdrawn, 0);
  assert.equal(result.items.length, 2);
  assert.equal(fixture.documents.get(`articles/${id(2)}`).publicationState, "live");
});

test("failed individual absence confirmation prevents every mirror write", async () => {
  const fixture = database();
  fixture.documents.set(`articles/${id(2)}`, {source: "webflow", sourceCollectionId: collectionId});
  const before = structuredClone(fixture.documents);
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async (url) => url.includes(`/items/${id(2)}/live`) ? response({}, 429) : response(envelope([item(1)]))}));
  assert.deepEqual(fixture.documents, before);
});

test("empty live catalog withdraws owned rows only after confirmed live 404", async () => {
  const fixture = database();
  fixture.documents.set(`articles/${id(2)}`, {source: "webflow", sourceCollectionId: collectionId});
  const result = await synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "local-fixture",
    now: () => 1000, transport: async (url) => url.includes(`/items/${id(2)}/live`) ? response({}, 404) : response(envelope([]))});
  assert.equal(result.items.length, 0);
  assert.equal(result.withdrawn, 1);
  assert.equal(isVisibleMirrorItem(fixture.documents.get(`articles/${id(2)}`)), false);
});

test("overlapping callers cannot both acquire an atomic lease", async () => {
  const fixture = database();
  const results = await Promise.allSettled([fixture.store.acquire("one", 2000), fixture.store.acquire("two", 2000)]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
});

test("event selection uses current canonical fields, refresh-only events never request an alert", async () => {
  const canonical = item(1, {fieldData: {name: "Current live headline"}});
  const synchronize = async () => ({items: [canonical], previousIDs: new Set()});
  const published = await synchronizeCatalogEvent({trigger: "collection_item_published", articleId: id(1), synchronize});
  assert.equal(published.notificationItem.fieldData.name, "Current live headline");
  for (const trigger of ["collection_item_deleted", "collection_item_unpublished", "collection_item_changed"]) {
    assert.equal((await synchronizeCatalogEvent({trigger, articleId: id(1), synchronize})).notificationItem, null);
  }
  assert.equal((await synchronizeCatalogEvent({trigger: "publish", articleId: id(2), synchronize})).notificationItem, null);
});

test("event selection propagates sync failure without permitting publication", async () => {
  await assert.rejects(synchronizeCatalogEvent({trigger: "publish", articleId: id(1),
    synchronize: async () => {throw new Error("HTTP 503");}}), /HTTP 503/);
});

test("server consumers reject withdrawal, archive and uninitialized publication", () => {
  for (const value of [null, {}, {...item(1), isDraft: true}, {...item(1), isArchived: true},
    {...item(1), publicationState: "withdrawn"}]) assert.equal(isVisibleMirrorItem(value), false);
  assert.equal(isVisibleMirrorItem(item(1)), true);
});

test("malformed lease cannot silently disable expiry fencing", async () => {
  const fixture = database();
  fixture.documents.set("cms_sync_leases/articles", {owner: "corrupt", expiresAt: "unknown"});
  await assert.rejects(fixture.store.acquire("new", 2000), /requires review/);
  await assert.rejects(fixture.store.commit("corrupt", [{id: id(1), value: item(1)}]), /lease lost/);
  assert.equal(fixture.documents.has(`articles/${id(1)}`), false);
});

test("content revision ignores object key order and transport metadata but preserves arrays", () => {
  const {contentRevision} = require("./webflowCatalog");
  const first = item(1, {fieldData: {name: "Story", content: "<p>Original</p>",
    image: {url: "https://example.invalid/a.jpg", alt: "Photo"}, topics: ["a", "b"]}});
  const reordered = {...first, lastUpdated: "2026-10-20T11:00:00Z", extraTransportField: "ignored",
    fieldData: {topics: ["a", "b"], image: {alt: "Photo", url: "https://example.invalid/a.jpg"},
      content: "<p>Original</p>", name: "Story"}};
  assert.match(contentRevision(first), /^cms-sha256-v1:[a-f0-9]{64}$/);
  assert.equal(contentRevision(first), contentRevision(reordered));
  assert.notEqual(contentRevision(first), contentRevision({...first,
    fieldData: {...first.fieldData, topics: ["b", "a"]}}));
});

test("corrections and deleted CMS fields change revision without changing publication date", () => {
  const {contentRevision} = require("./webflowCatalog");
  const original = item(1, {fieldData: {name: "Story", content: "Old", credit: "Photo A"}});
  for (const fieldData of [{...original.fieldData, content: "Corrected"},
    {...original.fieldData, name: "Corrected title"}, {name: "Story", content: "Old"}]) {
    assert.notEqual(contentRevision(original), contentRevision({...original, fieldData}));
  }
});

test("actual reconciliation writes corrected revision and preserves update timestamp", async () => {
  const fixture = database();
  let current = item(1, {fieldData: {name: "Story", content: "Old"}, lastUpdated: "2026-10-20T10:00:00Z"});
  const transport = async () => response(envelope([current]));
  const sync = () => synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "fixture", transport,
    now: () => 1000});
  await sync();
  const old = fixture.documents.get(`articles/${id(1)}`);
  current = {...current, fieldData: {...current.fieldData, content: "Corrected"}, lastUpdated: "2026-10-20T11:00:00Z"};
  await sync();
  const corrected = fixture.documents.get(`articles/${id(1)}`);
  assert.equal(corrected.lastPublished, old.lastPublished);
  assert.equal(corrected.lastUpdated, current.lastUpdated);
  assert.notEqual(corrected.contentRevision, old.contentRevision);
  assert.equal(corrected.fieldData.content, "Corrected");
  await sync();
  assert.equal(fixture.documents.get(`articles/${id(1)}`).contentRevision, corrected.contentRevision);
});

test("invalid update timestamp aborts catalog before any article write", async () => {
  const fixture = database();
  await assert.rejects(synchronizeLiveCatalog({store: fixture.store, collectionId, apiKey: "fixture",
    now: () => 1000, transport: async () => response(envelope([item(1, {lastUpdated: 42})]))}), /Invalid live/);
  assert.equal(fixture.documents.has(`articles/${id(1)}`), false);
});

const {ARTICLE_COLLECTION, DANISH_LOCALE, ENGLISH_LOCALE, isEnglishMirror,
  localeDocumentID} = require("./articleLocale");
function localizedFixture() {
  const f = database();
  f.collectionReads = [];
  // Exercise the actual adapter with authoritative article collection ownership.
  f.store = firestoreCatalogStore({db: {
    collection: (name) => ({doc: (key) => ({path: `${name}/${key}`}),
      get: async () => {f.collectionReads.push(name); return {docs: [...f.documents].filter(([key]) => key.startsWith(name + "/"))
        .map(([path, value]) => ({id: path.split("/")[1], data: () => structuredClone(value)}))};}}),
    runTransaction: async (callback) => {
      const pending = [];
      const result = await callback({get: async ({path}) => ({data: () => structuredClone(f.documents.get(path))}),
        set: ({path}, value) => pending.push([path, structuredClone(value)]),
        delete: ({path}) => pending.push([path, undefined])});
      for (const [path, value] of pending) value === undefined ? f.documents.delete(path) : f.documents.set(path, value);
      f.commits.push(pending); return result;
    },
  }, collection: "articles", collectionId: ARTICLE_COLLECTION, localizedArticles: true, timestamp: () => "local", now: () => 1000});
  return f;
}
const owned = (raw, locale, extra = {}) => ({id: localeDocumentID(raw, locale), sourceArticleID: raw,
  contentLanguage: locale === ENGLISH_LOCALE ? "en" : "da", cmsLocaleId: locale,
  source: "webflow", sourceCollectionId: ARTICLE_COLLECTION, publicationState: "live", ...extra});
const localizedRun = (fixture, transport) => synchronizeLiveCatalog({store: fixture.store,
  collectionId: ARTICLE_COLLECTION, apiKey: "injected-only", now: () => 1000, localizedArticles: true, transport});

test("localized sync pins both live scans, keeps shared raw IDs distinct and excludes EN observation", async () => {
  const f = localizedFixture(), urls = [];
  const result = await localizedRun(f, async (url) => {
    const u = new URL(url), locale = u.searchParams.get("cmsLocaleId"); urls.push(u);
    assert.equal(f.documents.has(`articles/${id(1)}`), false, "both scans precede writes");
    return response(envelope([item(1, {cmsLocaleId: locale, fieldData: {name: locale, slug: "same-slug"}})]));
  });
  assert.deepEqual(urls.map((u) => u.searchParams.get("cmsLocaleId")), [DANISH_LOCALE, ENGLISH_LOCALE]);
  assert.ok(urls.every((u) => u.pathname.endsWith("/items/live")));
  const da = f.documents.get(`articles/${id(1)}`), en = f.documents.get(`articles_en/en_${id(1)}`);
  assert.equal(da.id, id(1));assert.equal(da.cmsLocaleId, DANISH_LOCALE);
  assert.equal(en.id, `en_${id(1)}`);assert.equal(en.sourceArticleID, id(1));assert.equal(en.contentLanguage, "en");
  assert.equal(en.fieldData.name, ENGLISH_LOCALE);
  assert.equal(result.items.length, 2);
  assert.equal([...f.documents.keys()].filter((key) => key.startsWith("article_publication_observations/en_")).length, 0);
  // Even a changed/withdrawn English item cannot create an observation.
  assert.ok(f.commits.flat().every(([path]) => !path.includes("observations/en_")));
});

test("invalid EN locale, raw ID, duplicate or incomplete second scan causes no article writes", async () => {
  for (const english of [envelope([item(1)]), envelope([item(1, {cmsLocaleId: DANISH_LOCALE})]),
    envelope([item(1, {id: "A".repeat(24), cmsLocaleId: ENGLISH_LOCALE})]),
    envelope([item(1, {cmsLocaleId: ENGLISH_LOCALE}), item(1, {cmsLocaleId: ENGLISH_LOCALE})]),
    envelope([], 1)]) {
    const f = localizedFixture();
    f.documents.set(`articles/${id(8)}`, owned(id(8), DANISH_LOCALE));
    const before = structuredClone(f.documents);
    await assert.rejects(localizedRun(f, async (url) => response(new URL(url).searchParams.get("cmsLocaleId") ===
      DANISH_LOCALE ? envelope([item(1, {cmsLocaleId: DANISH_LOCALE})]) : english)));
    assert.deepEqual(f.documents, before);
  }
});

test("locale absence confirmations use raw IDs and own locale, never cross-withdraw shared IDs", async () => {
  const f = localizedFixture(), requests = [];
  f.documents.set(`articles/${id(1)}`, owned(id(1), DANISH_LOCALE));
  f.documents.set(`articles_en/en_${id(1)}`, owned(id(1), ENGLISH_LOCALE));
  // A malformed EN ownership row must never authorize a point read or withdrawal.
  f.documents.set(`articles_en/en_${id(2)}`, owned(id(3), ENGLISH_LOCALE));
  const result = await localizedRun(f, async (url) => {
    const u = new URL(url);requests.push(u);
    if (u.pathname.includes(`/items/${id(1)}/live`)) {
      assert.equal(u.searchParams.get("cmsLocaleId"), ENGLISH_LOCALE);
      return response({},404);
    }
    return response(envelope(u.searchParams.get("cmsLocaleId") === DANISH_LOCALE ?
      [item(1, {cmsLocaleId: DANISH_LOCALE})] : []));
  });
  assert.equal(result.withdrawn, 1);
  assert.equal(f.documents.get(`articles/${id(1)}`).publicationState, "live");
  assert.equal(f.documents.get(`articles_en/en_${id(1)}`).publicationState, "withdrawn");
  assert.equal(f.documents.get(`articles_en/en_${id(2)}`).publicationState, "live");
  assert.ok(requests.every((u) => !u.pathname.includes("/items/en_")));
});

test("failed EN point read prevents even valid DA writes; scan-shift recovered EN keeps mirror ID", async () => {
  for (const fail of [true,false]) {
    const f = localizedFixture();f.documents.set(`articles_en/en_${id(2)}`, owned(id(2), ENGLISH_LOCALE));
    const operation = localizedRun(f, async (url) => {
      const u = new URL(url), locale=u.searchParams.get("cmsLocaleId");
      if (u.pathname.includes(`/items/${id(2)}/live`)) return fail ? response({},503) : response(item(2,{cmsLocaleId:locale}));
      return response(envelope(locale === DANISH_LOCALE ? [item(1)] : []));
    });
    if (fail) {await assert.rejects(operation);assert.equal(f.documents.has(`articles/${id(1)}`),false);}
    else {const result=await operation;assert.equal(result.withdrawn,0);assert.equal(f.documents.get(`articles_en/en_${id(2)}`).publicationState,"live");}
  }
});

test("disabled generic sync retains legacy DA output and never point-reads or withdraws EN mirrors", async () => {
  const f = database();f.documents.set(`articles_en/en_${id(1)}`,{...owned(id(1),ENGLISH_LOCALE),sourceCollectionId:collectionId});
  const result=await synchronizeLiveCatalog({store:f.store,collectionId,apiKey:"injected",now:()=>1000,
    transport:async (url)=>{assert.equal(new URL(url).searchParams.has("cmsLocaleId"),false);assert.ok(!url.includes("/items/en_"));return response(envelope([item(1)]));}});
  const da=f.documents.get(`articles/${id(1)}`);assert.equal(da.contentLanguage,undefined);assert.equal(da.sourceArticleID,undefined);assert.equal(da.cmsLocaleId,null);
  assert.equal(result.withdrawn,0);assert.equal(f.documents.get(`articles_en/en_${id(1)}`).publicationState,"live");
});

test("authoritative locale identity does not inspect editorial text or slug", () => {
  assert.equal(isEnglishMirror(`en_${id(1)}`,{}),true);
  assert.equal(isEnglishMirror(id(1),{cmsLocaleId:ENGLISH_LOCALE}),true);
  assert.equal(isEnglishMirror(id(1),{contentLanguage:"en"}),true);
  assert.equal(isEnglishMirror(id(1),{fieldData:{name:"The English title",slug:"story-en"}}),false);
  assert.throws(()=>localeDocumentID(id(1),"unknown"));
});

test("localized pagination guards stay active across EN pages and cannot write partial DA results", async () => {
  const f=localizedFixture();
  await assert.rejects(localizedRun(f,async (url)=>{
    const u=new URL(url),locale=u.searchParams.get("cmsLocaleId"),offset=Number(u.searchParams.get("offset"));
    if(locale===DANISH_LOCALE)return response(envelope([item(1)]));
    return response(offset ? envelope([item(2,{cmsLocaleId:locale})],3,offset) :
      envelope([item(1,{cmsLocaleId:locale})],2));
  }),/changed during scan/);
  assert.equal([...f.documents.keys()].filter((p)=>p.startsWith("articles/")).length,0);
});

test("DA absence confirmation cannot query or withdraw a same-ID live EN mirror", async () => {
  const f=localizedFixture();
  f.documents.set(`articles/${id(4)}`,owned(id(4),DANISH_LOCALE,{cmsLocaleId:null}));
  f.documents.set(`articles_en/en_${id(4)}`,owned(id(4),ENGLISH_LOCALE));
  const result=await localizedRun(f,async(url)=>{
    const u=new URL(url),locale=u.searchParams.get("cmsLocaleId");
    if(u.pathname.includes(`/items/${id(4)}/live`)) {assert.equal(locale,DANISH_LOCALE);return response({},404);}
    return response(envelope(locale===ENGLISH_LOCALE?[item(4,{cmsLocaleId:locale})]:[]));
  });
  assert.equal(result.withdrawn,1);assert.equal(f.documents.get(`articles/${id(4)}`).publicationState,"withdrawn");
  assert.equal(f.documents.get(`articles_en/en_${id(4)}`).publicationState,"live");
});

test("English adapter writes never create first-observation records, even for English Danish-text content", async () => {
  const f=localizedFixture();
  await localizedRun(f,async(url)=>{
    const locale=new URL(url).searchParams.get("cmsLocaleId");
    return response(envelope(locale===ENGLISH_LOCALE?[item(6,{cmsLocaleId:locale,
      fieldData:{name:"Dansk tekst i engelsk CMS",slug:"helt-almindelig"}})]:[]));
  });
  assert.equal(f.documents.has(`articles_en/en_${id(6)}`),true);
  assert.deepEqual([...f.documents.keys()].filter((p)=>p.startsWith("article_publication_observations/")),[]);
});

test("isolated adapter leaves whole primary articles reads DA-only for older locale-unaware clients", async () => {
  const f=localizedFixture();
  await localizedRun(f,async(url)=>response(envelope([item(1,{cmsLocaleId:new URL(url).searchParams.get("cmsLocaleId")})])));
  const oldClientRows=[...f.documents].filter(([path])=>path.startsWith("articles/"));
  assert.deepEqual(oldClientRows.map(([path])=>path),[`articles/${id(1)}`]);
  assert.equal(oldClientRows[0][1].contentLanguage,"da");
  assert.equal(f.documents.get(`articles_en/en_${id(1)}`).contentLanguage,"en");
  const listed=await f.store.list();
  assert.deepEqual(listed.map(row=>[row.id,row.mirrorCollection]),[[id(1),"articles"],[`en_${id(1)}`,"articles_en"]]);
  assert.ok(f.commits.flat().every(([path])=>!path.startsWith("articles/en_")));
});

test("disabled adapter never reads the isolated EN collection and rejects EN writes before any mutation", async () => {
  const f=database();
  f.documents.set(`articles_en/en_${id(1)}`,owned(id(1),ENGLISH_LOCALE));
  assert.deepEqual(await f.store.list(),[]);
  assert.deepEqual(f.collectionReads,["articles"]);
  await f.store.acquire("local",2000);
  const before=structuredClone(f.documents);
  for(const value of [owned(id(1),ENGLISH_LOCALE),{...item(1),cmsLocaleId:ENGLISH_LOCALE}]) {
    await assert.rejects(f.store.commit("local",[{id:value.id,value}]),/English article destination/);
    assert.deepEqual(f.documents,before);
  }
});

test("EN destination requires exact mirror contract and refuses an entire mixed chunk on mismatch", async () => {
  const f=localizedFixture();await f.store.acquire("local",2000);
  const before=structuredClone(f.documents);
  await assert.rejects(f.store.commit("local",[
    {id:id(1),value:owned(id(1),DANISH_LOCALE)},
    {id:`en_${id(1)}`,value:owned(id(2),ENGLISH_LOCALE)},
  ]),/English article destination/);
  assert.deepEqual(f.documents,before);
});

test("EN withdrawal authority is location-bound and never moves an incorrectly placed row", async () => {
  const f=localizedFixture();
  // Historical/unreviewed misplaced data cannot authorize a read or cleanup.
  f.documents.set(`articles/en_${id(1)}`,owned(id(1),ENGLISH_LOCALE));
  const result=await localizedRun(f,async(url)=>{
    assert.ok(!new URL(url).pathname.includes(`/items/${id(1)}/live`));
    return response(envelope([]));
  });
  assert.equal(result.withdrawn,0);
  assert.equal(f.documents.get(`articles/en_${id(1)}`).publicationState,"live");
  assert.equal(f.documents.has(`articles_en/en_${id(1)}`),false);
});
