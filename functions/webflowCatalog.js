// No Firebase initialization. Transport, clock and storage are injected for tests.
const {randomUUID, createHash} = require("node:crypto");
const {OBSERVATIONS, POLICY_COLLECTION, POLICY_ID, firstObservation} = require("./publicationPolicy");

// Canonicalize keys recursively; preserve arrays, values and field deletion.
// This token is opaque to clients and never compared lexicographically.
function canonicalJSON(value) {
  if (Array.isArray(value)) return "[" + value.map(canonicalJSON).join(",") + "]";
  if (value && typeof value === "object") return "{" + Object.keys(value).sort()
    .map((key) => JSON.stringify(key) + ":" + canonicalJSON(value[key])).join(",") + "}";
  return JSON.stringify(value);
}
function contentRevision(item) {
  const value = {id: item.id, fieldData: item.fieldData,
    createdOn: item.createdOn ?? null, lastPublished: item.lastPublished};
  return "cms-sha256-v1:" + createHash("sha256").update(canonicalJSON(value)).digest("hex");
}

const {ARTICLE_COLLECTION, DANISH_LOCALE, ENGLISH_LOCALE, ENGLISH_ARTICLES_COLLECTION, isEnglishMirror, localeDocumentID, ownedLocaleDocument} = require("./articleLocale");
const ID = /^[a-f\d]{24}$/i;
function normalizeLiveItem(item) {
  if (!item || !ID.test(item.id) || !item.fieldData || typeof item.fieldData !== "object" ||
      Array.isArray(item.fieldData) || typeof item.lastPublished !== "string" ||
      !Number.isFinite(Date.parse(item.lastPublished)) || typeof item.isDraft !== "boolean" ||
      typeof item.isArchived !== "boolean" ||
      (item.lastUpdated != null && (typeof item.lastUpdated !== "string" ||
        !Number.isFinite(Date.parse(item.lastUpdated))))) throw new Error("Invalid live CMS item");
  return item.isArchived ? null : {...item, isDraft: false};
}

function liveItemsURL(collectionId, offset = 0, limit = 100, cmsLocaleId) {
  if (!ID.test(collectionId)) throw new Error("Invalid Webflow collection id");
  const url = new URL(`https://api.webflow.com/v2/collections/${collectionId}/items/live`);
  if (cmsLocaleId !== undefined) {
    if (![DANISH_LOCALE, ENGLISH_LOCALE].includes(cmsLocaleId)) throw new Error("Unsupported CMS locale");
    url.searchParams.set("cmsLocaleId", cmsLocaleId);
  }
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("offset", String(offset));
  // Creation date changes less frequently than lastPublished during a scan.
  url.searchParams.set("sortBy", "createdOn");
  url.searchParams.set("sortOrder", "asc");
  return url.toString();
}

async function fetchLiveCatalog({collectionId, apiKey, transport = fetch,
  now = Date.now, deadline = now() + 90000, maxItems = 10000, limit = 100, cmsLocaleId}) {
  if (typeof apiKey !== "string" || !apiKey.trim()) throw new Error("WEBFLOW_API_KEY is missing");
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Invalid page limit");
  const seen = new Set();
  const result = [];
  let offset = 0;
  let total;
  while (true) {
    const remaining = deadline - now();
    if (remaining <= 0) throw new Error("Webflow scan deadline exceeded");
    const response = await transport(liveItemsURL(collectionId, offset, limit, cmsLocaleId), {
      headers: {Authorization: `Bearer ${apiKey.trim()}`},
      signal: AbortSignal.timeout(Math.min(remaining, 20000)),
    });
    // Never include response bodies (which may contain editorial content) in errors.
    if (!response.ok) throw new Error(`Webflow live scan HTTP ${response.status} at offset ${offset}`);
    const payload = await response.json();
    if (now() >= deadline) throw new Error("Webflow scan deadline exceeded");
    const page = payload?.pagination;
    const items = payload?.items;
    if (!Array.isArray(items) || !page || !Number.isSafeInteger(page.total) ||
        page.total < 0 || page.total > maxItems || page.offset !== offset ||
        !Number.isInteger(page.limit) || page.limit < 1 || page.limit > limit ||
        items.length > page.limit || offset + items.length > page.total) {
      throw new Error("Invalid Webflow pagination envelope");
    }
    if (total !== undefined && total !== page.total) throw new Error("Webflow catalog changed during scan");
    total = page.total;
    for (const item of items) {
      const normalized = normalizeLiveItem(item);
      validateLocaleItem(item, cmsLocaleId);
      if (seen.has(item.id)) throw new Error("Duplicate live CMS item (including unsupported locale collision)");
      seen.add(item.id);
      if (normalized) {
        // Live endpoint supplies published fieldData even when staged edits exist.
        result.push(normalized);
      }
    }
    offset += items.length; // Raw count, before any publication filtering.
    if (offset === total) return result;
    if (!items.length) throw new Error("Webflow scan ended before pagination total");
  }
}

function validateLocaleItem(item, locale) {
  if (locale === undefined) return;
  localeDocumentID(item.id, locale);
  if (item.cmsLocaleId !== locale && !(locale === DANISH_LOCALE && item.cmsLocaleId == null)) {
    throw new Error("Live CMS locale mismatch");
  }
}

async function fetchLiveItem({collectionId, itemId, apiKey, transport = fetch,
  now = Date.now, deadline = now() + 20000, cmsLocaleId}) {
  if (!ID.test(itemId) || !ID.test(collectionId)) throw new Error("Invalid live CMS identifier");
  const remaining = deadline - now();
  if (remaining <= 0) throw new Error("Webflow scan deadline exceeded");
  if (typeof apiKey !== "string" || !apiKey.trim()) throw new Error("WEBFLOW_API_KEY is missing");
  const url = new URL(`https://api.webflow.com/v2/collections/${collectionId}/items/${itemId}/live`);
  if (cmsLocaleId !== undefined) {
    localeDocumentID(itemId, cmsLocaleId);
    url.searchParams.set("cmsLocaleId", cmsLocaleId);
  }
  const response = await transport(url.toString(), {
    headers: {Authorization: `Bearer ${apiKey.trim()}`}, signal: AbortSignal.timeout(Math.min(remaining, 20000)),
  });
  if (now() >= deadline) throw new Error("Webflow scan deadline exceeded");
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Webflow live item HTTP ${response.status}`);
  const item = await response.json();
  if (now() >= deadline) throw new Error("Webflow scan deadline exceeded");
  if (item?.id !== itemId) throw new Error("Webflow live item identifier mismatch");
  const normalized = normalizeLiveItem(item);
  validateLocaleItem(item, cmsLocaleId);
  return normalized;
}

/**
 * All article/metadata sync entrypoints share a fenced, expiring store lease.
 * A failed or unstable fetch never reaches writes/withdrawals. Firestore commits
 * are chunk-atomic, not a full-catalog transaction; retries repair partial commits.
 */
async function synchronizeLiveCatalog({store, collectionId, apiKey, transport,
  now = Date.now, owner = randomUUID(), leaseMs = 180000, fetchOptions = {}, localizedArticles = false}) {
  if (localizedArticles && collectionId !== ARTICLE_COLLECTION) throw new Error("Localized mirror requires article collection");
  await store.acquire(owner, now() + leaseMs);
  try {
    const deadline = now() + 90000;
    const previous = await store.list();
    // Both complete locale scans (and all point confirmations) precede the first write.
    const scopes = localizedArticles ? [DANISH_LOCALE, ENGLISH_LOCALE] : [undefined];
    const scans = [];
    for (const locale of scopes) {
      const rows = await fetchLiveCatalog({collectionId, apiKey, transport, now, deadline,
        ...fetchOptions, ...(localizedArticles ? {cmsLocaleId: locale} : {})});
      scans.push({locale, rows});
    }
    const items = [], writes = [], published = new Set();
    for (const {locale, rows} of scans) {
      const mirrorID = (raw) => localizedArticles ? localeDocumentID(raw, locale) : raw;
      const liveWrite = (item) => {
        const id = mirrorID(item.id);
        return {id, value: {id, fieldData: item.fieldData, isDraft: false, isArchived: false,
          createdOn: item.createdOn ?? null, lastPublished: item.lastPublished,
          lastUpdated: item.lastUpdated ?? null, cmsLocaleId: item.cmsLocaleId ?? null,
          contentRevision: contentRevision(item), source: "webflow", sourceCollectionId: collectionId,
          publicationState: "live", ...(localizedArticles ? {sourceArticleID: item.id,
            contentLanguage: locale === ENGLISH_LOCALE ? "en" : "da", cmsLocaleId: locale} : {})}};
      };
      const accept = (item) => {
        const write = liveWrite(item);
        published.add(write.id); writes.push(write);
        items.push({...item, id: write.id, ...(localizedArticles ? {
          sourceArticleID: item.id, contentLanguage: locale === ENGLISH_LOCALE ? "en" : "da",
          cmsLocaleId: locale} : {})});
      };
      rows.forEach(accept);
      for (const doc of previous) {
        // Never treat an English mirror as a raw CMS ID, even while activation is off.
        const raw = localizedArticles ? ownedLocaleDocument(doc, collectionId, locale) :
          (doc.data.source === "webflow" && doc.data.sourceCollectionId === collectionId &&
            !isEnglishMirror(doc.id, doc.data) && ID.test(doc.id) ? doc.id : null);
        if (!raw || published.has(doc.id) || doc.data.publicationState === "withdrawn") continue;
        const current = await fetchLiveItem({collectionId, itemId: raw, apiKey, transport, now, deadline,
          ...(localizedArticles ? {cmsLocaleId: locale} : {})});
        if (current) {accept(current); continue;}
        writes.push({id: doc.id, value: {id: doc.id, fieldData: {slug: doc.data.fieldData?.slug || ""},
          isDraft: true, isArchived: true, lastPublished: null, source: "webflow",
          sourceCollectionId: collectionId, publicationState: "withdrawn",
          ...(localizedArticles ? {sourceArticleID: raw,
            contentLanguage: locale === ENGLISH_LOCALE ? "en" : "da", cmsLocaleId: locale} : {})}});
      }
    }
    for (let index = 0; index < writes.length; index += 100) {
      await store.commit(owner, writes.slice(index, index + 100));
    }
    return {items, previousIDs: new Set(previous.map((doc) => doc.id)),
      unownedAbsentIDs: previous.filter((doc) => !published.has(doc.id) &&
        (doc.data.source !== "webflow" || doc.data.sourceCollectionId !== collectionId)).map((doc) => doc.id),
      withdrawn: writes.length - items.length};
  } finally {
    await store.release(owner);
  }
}

/** Production adapter; callers supply an already configured Firebase Admin DB. */
function firestoreCatalogStore({db, collection, collectionId, timestamp, now = Date.now, localizedArticles = false}) {
  if (localizedArticles && (collection !== "articles" || collectionId !== ARTICLE_COLLECTION)) {
    throw new Error("Localized adapter requires article collection");
  }
  const lease = db.collection("cms_sync_leases").doc(collection);
  const target = db.collection(collection);
  // Separate top-level collection keeps older locale-unaware clients isolated.
  const english = localizedArticles ? db.collection(ENGLISH_ARTICLES_COLLECTION) : null;
  return {
    acquire: (owner, expiresAt) => db.runTransaction(async (tx) => {
      const snapshot = await tx.get(lease);
      const current = snapshot.data();
      if (current?.owner && (!Number.isFinite(current.expiresAt) || current.expiresAt > now())) {
        throw new Error("CMS sync already running or lease requires review");
      }
      tx.set(lease, {owner, expiresAt, collectionId});
    }),
    list: async () => {
      const snapshot = await target.get();
      const primary = snapshot.docs.map((doc) => ({id: doc.id, data: doc.data(), mirrorCollection: collection}));
      if (!english) return primary;
      const secondary = await english.get();
      return primary.concat(secondary.docs.map((doc) => ({id: doc.id, data: doc.data(),
        mirrorCollection: ENGLISH_ARTICLES_COLLECTION})));
    },
    commit: (owner, writes) => db.runTransaction(async (tx) => {
      const snapshot = await tx.get(lease);
      const current = snapshot.data();
      if (current?.owner !== owner || !Number.isFinite(current.expiresAt) || current.expiresAt <= now()) {
        throw new Error("CMS sync lease lost");
      }
      // Destination is independently validated by the adapter, not trusted from
      // an engine-provided collection string. Disabled mode cannot write EN.
      const destinations = writes.map(({id, value}) => {
        if (collection !== "articles") return target.doc(id);
        if (isEnglishMirror(id, value)) {
          if (!english || !ownedLocaleDocument({id, data: value, mirrorCollection: ENGLISH_ARTICLES_COLLECTION},
              collectionId, ENGLISH_LOCALE)) throw new Error("English article destination unavailable");
          return english.doc(id);
        }
        if (!ID.test(id)) throw new Error("Invalid Danish mirror identifier");
        return target.doc(id);
      });
      // Persist first observation in the same transaction as the mirror write.
      // Every caller (including scheduler) participates; metadata sync does not.
      let observations = [];
      if (collection === "articles") {
        const policy = (await tx.get(db.collection(POLICY_COLLECTION).doc(POLICY_ID))).data();
        const snapshots = await Promise.all(writes.filter(({id, value}) => !isEnglishMirror(id, value)).map(async ({id, value}) => {
          const ref = db.collection(OBSERVATIONS).doc(id);
          const [existing, mirror] = await Promise.all([tx.get(ref), tx.get(target.doc(id))]);
          return {ref, existing: existing.data(), value: firstObservation({articleId: id, collectionId, value,
            existed: !!mirror.data(), policy, now: now()})};
        }));
        observations = snapshots.filter((entry) => !entry.existing);
      }
      for (const observation of observations) tx.set(observation.ref, observation.value);
      for (let index = 0; index < writes.length; index++) {
        // Replacement removes CMS fields deleted since the previous revision.
        tx.set(destinations[index], {...writes[index].value, syncedAt: timestamp()});
      }
    }),
    release: (owner) => db.runTransaction(async (tx) => {
      const snapshot = await tx.get(lease);
      if (snapshot.data()?.owner === owner) tx.delete(lease);
    }),
  };
}

function isVisibleMirrorItem(data) {
  return !!data && data.isDraft !== true && data.isArchived !== true &&
    data.publicationState !== "withdrawn" && typeof data.lastPublished === "string" &&
    !!data.lastPublished.trim();
}

function catalogEventAction(trigger) {
  if (["collection_item_published", "publish"].includes(trigger)) return "publish";
  if (["collection_item_unpublished", "collection_item_deleted", "collection_item_changed",
    "collection_item_created"].includes(trigger)) return "refresh";
  return "ignore";
}

async function synchronizeCatalogEvent({trigger, articleId, synchronize}) {
  const action = catalogEventAction(trigger);
  if (action === "ignore") throw new Error("Unsupported catalog event");
  const result = await synchronize();
  return {...result, notificationItem: action === "publish" ?
    result.items.find((item) => item.id === articleId) || null : null};
}

module.exports = {contentRevision, liveItemsURL, fetchLiveCatalog, synchronizeLiveCatalog,
  firestoreCatalogStore, catalogEventAction, fetchLiveItem, isVisibleMirrorItem, synchronizeCatalogEvent};
