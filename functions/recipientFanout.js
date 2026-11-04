// SDK-free staging and transport receipts. Deliberately not connected to Cloud triggers.
const {randomUUID} = require("node:crypto");
const {COLLECTION: PARENTS, valid: validParent, isUntouchedArticleIntent, classifySendError, withSendDeadline} = require("./pushOutbox");
const {hash, eventDescriptor, planRecipients, resolvePendingDelivery} = require("./recipientRouting");
const {INSTALLATIONS} = require("./recipientRegistry");
const {narrationSource} = require("./podcastManifest");
const {isEnglishArticleContent} = require("./notificationPolicy");
const COLLECTION = "article_push_deliveries", PLANS = "article_push_recipient_plans", PAGES = "article_push_recipient_pages";
const {INPUT_ROOTS, INPUT_PAGES, PAGE_SIZE, SNAPSHOT_AGE_MS, digest, compact, pageDigest, validDescriptor, validExpected,
  validRoot, validPage, inputID, inputPageID, acceptedInput, createFrozenInputStore} = require("./recipientFrozenInput");
const MODE = "installations-v1", TERMINAL = Number.MAX_SAFE_INTEGER;
const envelopeHash = (parent) => digest(parent.envelope);
const pageID = (planId, index) => `${planId}-${index}`;
const validID = (id) => typeof id === "string" && /^article-[a-f\d]{64}$/.test(id);
function categories(article) {
  const fields = article?.fieldData || {}, multi = fields["topics-multi-ref"] || fields.topics || [];
  if (!Array.isArray(multi) || multi.length > 100) throw new Error("Invalid article categories");
  return eventDescriptor({id: "categories", family: "article", articleId: article.id,
    sourceRevision: article.contentRevision, categoryIds: [...new Set([...(fields.topic ? [fields.topic] : []), ...multi])]}).categoryIds;
}
function makeDeviceMessage(parent, child, token) {
  const message = structuredClone(parent.envelope);
  delete message.topic;delete message.condition;delete message.token;
  message.token = token;
  message.data = {...message.data, notification_id: child.id};
  message.apns = {...message.apns, headers: {...message.apns?.headers, "apns-collapse-id": child.id.slice(-64)}};
  message.android = {...message.android, notification: {...message.android?.notification, tag: child.id}};
  // The token isn't part of the APNs payload; nevertheless bound the entire transport request.
  if (Buffer.byteLength(JSON.stringify(message)) > 8192 || Buffer.byteLength(JSON.stringify({...message, token: undefined})) > 4096) {
    throw new Error("Device notification payload exceeds budget");
  }
  return message;
}
function retryDelay(id, attempts, error, now) {
  const jitter = parseInt(hash(`${id}:${attempts}`).slice(0, 8), 16) % 30000;
  const raw = error?.httpResponse?.headers?.["retry-after"];
  let after = /^\d{1,9}$/.test(String(raw || "")) ? Number(raw) * 1000 : Date.parse(raw) - now;
  if (!Number.isFinite(after) || after < 0) after = 0;
  return Math.max(Math.min(21600000, 60000 * 2 ** Math.min(attempts - 1, 8)) + jitter, after);
}
function createRecipientFanoutStore({db, collectionId, now = Date.now, leaseMs = 300000, maximumAttempts = 5}) {
  if (!Number.isFinite(leaseMs) || leaseMs <= 0 || !Number.isInteger(maximumAttempts) || maximumAttempts < 1) throw new Error("Invalid fanout policy");
  const parents = db.collection(PARENTS), children = db.collection(COLLECTION), plans = db.collection(PLANS), pages = db.collection(PAGES);
  const inputRoots = db.collection(INPUT_ROOTS), inputPages = db.collection(INPUT_PAGES), frozenInput = createFrozenInputStore({db, now});
  const binding = (parentId, parent, generation) => validParent(parentId, parent) && parent.deliveryMode === MODE &&
    Number.isSafeInteger(generation) && generation > 0 && parent.fanout?.generation === generation &&
    parent.fanout.planId === `${parentId}-${generation}` && /^[a-f\d]{64}$/.test(parent.fanout.planHash || "") &&
    parent.fanout.sourceRevision === parent.sourceRevision && parent.fanout.envelopeHash === envelopeHash(parent);
  const childBinding = (parentId, parent, generation, child, id) => binding(parentId, parent, generation) &&
    child?.schemaVersion === 1 && validDescriptor(compact(child), parentId) && Number.isSafeInteger(child.attempts) && child.attempts >= 0 &&
    Number.isFinite(child.availableAtMs) && child.id === id && child.parentId === parentId &&
    child.generation === generation && child.sourceRevision === parent.sourceRevision && child.envelopeHash === parent.fanout.envelopeHash;
  const matches = (parent, article) => {
    try {return !isEnglishArticleContent(article.fieldData, article) &&
      narrationSource(article, {collectionId, slug: parent.slug, articleId: parent.articleId}).sourceContentRevision === parent.sourceRevision;} catch {return false;}
  };
  const sourceReads = (tx, parent) => [tx.get(db.collection("articles").doc(parent.articleId)), tx.get(db.collection("notified_articles").doc(parent.articleId))];
  const planBinding = (parentId, parent, generation, plan) => [1, 2].includes(plan?.schemaVersion) &&
    plan.parentId === parentId && plan.generation === generation && plan.planHash === parent.fanout.planHash &&
    /^[a-f\d]{64}$/.test(plan.snapshotHash || "") && Number.isSafeInteger(plan.snapshotAtMs) && plan.snapshotAtMs > 0 &&
    validExpected(plan.expected, plan.total) && Number.isSafeInteger(plan.stagedPages) && plan.stagedPages >= 0 && plan.stagedPages <= plan.expected.length &&
    Number.isSafeInteger(plan.stagedRecipients) && plan.stagedRecipients >= 0 && plan.stagedRecipients <= plan.total &&
    ["planning", "ready"].includes(plan.phase) && (plan.schemaVersion === 1 || (inputID(plan.frozenRootId) && Number.isInteger(plan.nextStagePage) && plan.nextStagePage >= 0 &&
      plan.nextStagePage <= plan.stagedPages && plan.nextStagePage <= plan.expected.length));
  const acceptedPlan = async (tx, parentId, parent, plan) => {
    if (plan.schemaVersion === 1) {const time = now();return Number.isSafeInteger(time) && time > 0 && time >= plan.snapshotAtMs && time - plan.snapshotAtMs <= SNAPSHOT_AGE_MS;}
    const root = (await tx.get(inputRoots.doc(plan.frozenRootId))).data();
    return acceptedInput(plan.frozenRootId, root, parentId, parent, plan, now());
  };
  const store = {
    async startPlan({parentId, event: input, registrations, coverage}) {
      if (!validID(parentId)) throw new Error("Invalid fanout parent");
      const normalized = eventDescriptor(input), event = {id: normalized.id, family: normalized.family, articleId: normalized.articleId,
        sourceRevision: normalized.sourceRevision, categoryIds: normalized.categoryIds};
      if (event.id !== parentId || event.family !== "article") throw new Error("Fanout event identity mismatch");
      // Snapshot caller data before the first await; freshness cannot be renewed by mutating an old roster.
      coverage = structuredClone(coverage);
      const result = planRecipients({event, registrations, coverage, now: now()});
      if (result.status !== "ready") return {status: "blocked", issues: result.issues};
      const batches = [];
      for (let offset = 0; offset < result.deliveries.length; offset += PAGE_SIZE) batches.push(result.deliveries.slice(offset, offset + PAGE_SIZE).map(compact));
      const expected = batches.map((items) => ({hash: pageDigest(items), count: items.length}));
      const snapshotHash = digest([coverage.inventoryHash, coverage.snapshotAtMs,
        [...coverage.expected].sort((a, b) => a.installationId.localeCompare(b.installationId)).map((r) => [r.installationId, r.digest])]);
      if (!validExpected(expected, result.deliveries.length) || batches.some((b) => Buffer.byteLength(JSON.stringify(b)) > 128000)) throw new Error("Fanout manifest exceeds budget");
      const check = async (tx, parent) => {
        if (!validParent(parentId, parent)) return "invalid_parent";
        const [article, legacy] = await Promise.all(sourceReads(tx, parent));
        const time = now();
        if (!Number.isSafeInteger(time) || time <= 0 || !matches(parent, article.data()) || legacy.exists || parent.expiresAtMs <= time || time < coverage.snapshotAtMs || time - coverage.snapshotAtMs > SNAPSHOT_AGE_MS) return "source_or_snapshot_changed";
        let canonicalCategories;
        try {canonicalCategories = categories(article.data());} catch {return "invalid_categories";}
        if (event.articleId !== parent.articleId || event.sourceRevision !== parent.sourceRevision || digest(event.categoryIds) !== digest(canonicalCategories)) return "event_source_mismatch";
        return null;
      };
      // Read preflight only. Input commits below may race a topic/source worker and confer no authority.
      const preflight = await db.runTransaction(async (tx) => {
        const parent = (await tx.get(parents.doc(parentId))).data(), issue = await check(tx, parent);
        return issue ? {issue} : {parent};
      });
      if (preflight.issue) return {status: "blocked", issues: [preflight.issue]};
      const original = preflight.parent, payloadHash = envelopeHash(original), planHash = digest([event, payloadHash, snapshotHash, expected]);
      const frozenRootId = await frozenInput.persist({parentId, sourceRevision: original.sourceRevision, envelopeHash: payloadHash, event,
        snapshotHash, snapshotAtMs: coverage.snapshotAtMs, expected, total: result.deliveries.length, expiresAtMs: original.expiresAtMs, batches});
      return db.runTransaction(async (tx) => {
        const ref = parents.doc(parentId), parent = (await tx.get(ref)).data(), issue = await check(tx, parent);
        if (issue) return {status: "blocked", issues: [issue]};
        const root = (await tx.get(inputRoots.doc(frozenRootId))).data();
        const samePlan = parent.deliveryMode === MODE && parent.fanout?.planHash === planHash && parent.fanout.frozenRootId === frozenRootId && ["planning", "ready"].includes(parent.fanout.phase);
        if (samePlan && !binding(parentId, parent, parent.fanout.generation)) return {status: "blocked", issues: ["invalid_existing_plan"]};
        const existing = samePlan ? (await tx.get(plans.doc(parent.fanout.planId))).data() : null;
        // The acceptance clock is captured after every transaction read and reused for all final guards/writes.
        const acceptedAtMs = now();
        if (!Number.isSafeInteger(acceptedAtMs) || acceptedAtMs <= 0 || acceptedAtMs < coverage.snapshotAtMs || acceptedAtMs - coverage.snapshotAtMs > SNAPSHOT_AGE_MS ||
            parent.expiresAtMs <= acceptedAtMs || !validRoot(frozenRootId, root) || root.phase !== "sealed" || root.parentId !== parentId || root.sourceRevision !== parent.sourceRevision ||
            root.envelopeHash !== envelopeHash(parent) || root.expiresAtMs !== parent.expiresAtMs || root.sealedAtMs > acceptedAtMs) return {status: "blocked", issues: ["frozen_input_changed"]};
        const response = (status, generation) => ({status, generation, frozenRootId, total: result.deliveries.length,
          pages: batches.map((deliveries, pageIndex) => ({pageIndex, deliveries}))});
        if (samePlan) {
          if (!binding(parentId, parent, parent.fanout.generation) || !planBinding(parentId, parent, parent.fanout.generation, existing) ||
              !acceptedInput(frozenRootId, root, parentId, parent, existing, acceptedAtMs)) return {status: "blocked", issues: ["invalid_existing_plan"]};
          return response(parent.fanout.phase, parent.fanout.generation);
        }
        if (!isUntouchedArticleIntent(parent, acceptedAtMs)) return {status: "blocked", issues: ["transport_already_started"]};
        if (parent.deliveryMode && parent.deliveryMode !== MODE) return {status: "blocked", issues: ["foreign_delivery_mode"]};
        const generation = (parent.fanout?.generation || 0) + 1, planId = `${parentId}-${generation}`;
        if (!Number.isSafeInteger(generation) || generation <= 0) throw new Error("Invalid fanout generation");
        tx.set(plans.doc(planId), {schemaVersion: 2, parentId, generation, planHash, expected, total: result.deliveries.length,
          frozenRootId, acceptedAtMs, expiresAtMs: root.expiresAtMs, snapshotHash, snapshotAtMs: coverage.snapshotAtMs,
          createdAtMs: acceptedAtMs, stagedPages: 0, stagedRecipients: 0, nextStagePage: 0, phase: "planning"});
        tx.set(ref, {...parent, deliveryMode: MODE, availableAtMs: TERMINAL, leaseToken: null, leaseExpiresAtMs: 0,
          fanout: {generation, planId, planHash, frozenRootId, phase: "planning", sourceRevision: parent.sourceRevision, envelopeHash: payloadHash, event}});
        return response("planning", generation);
      });
    },
    async stagePage({parentId, generation, pageIndex, deliveries}) {
      deliveries = structuredClone(deliveries);
      if (!validID(parentId) || !Number.isInteger(pageIndex) || pageIndex < 0 || !Array.isArray(deliveries) || !deliveries.length ||
          deliveries.length > PAGE_SIZE || deliveries.some((r) => !validDescriptor(r, parentId)) || Buffer.byteLength(JSON.stringify(deliveries)) > 128000) return false;
      return db.runTransaction(async (tx) => {
        const parent = (await tx.get(parents.doc(parentId))).data();
        if (!binding(parentId, parent, generation) || !["planning", "ready"].includes(parent.fanout.phase)) return false;
        const planRef = plans.doc(parent.fanout.planId), pageRef = pages.doc(pageID(parent.fanout.planId, pageIndex));
        const [manifest, staged, ...oldChildren] = await Promise.all([tx.get(planRef), tx.get(pageRef), ...deliveries.map((r) => tx.get(children.doc(r.id)))]);
        const plan = manifest.data(), proof = plan?.expected?.[pageIndex], pageHash = pageDigest(deliveries);
        if (!planBinding(parentId, parent, generation, plan) || !proof || proof.hash !== pageHash || proof.count !== deliveries.length) return false;
        // Schema2 always checks its sealed input; callers cannot substitute a fresh registry snapshot.
        if (plan.schemaVersion === 2) {
          const [rootSnap, frozenPage] = await Promise.all([tx.get(inputRoots.doc(plan.frozenRootId)), tx.get(inputPages.doc(inputPageID(plan.frozenRootId, pageIndex)))]);
          if (!acceptedInput(plan.frozenRootId, rootSnap.data(), parentId, parent, plan, now()) || !validPage(plan.frozenRootId, rootSnap.data(), frozenPage.data(), pageIndex) ||
              pageDigest(frozenPage.data().deliveries) !== pageHash) return false;
        }
        if (staged.exists) {
          const receipt = staged.data();
          if (receipt.schemaVersion !== 1 || receipt.parentId !== parentId || receipt.generation !== generation || receipt.pageIndex !== pageIndex || receipt.hash !== pageHash ||
              digest(receipt.ids) !== digest(deliveries.map((r) => r.id))) return false;
          if (plan.schemaVersion === 2 && plan.nextStagePage === pageIndex && plan.phase === "planning") tx.set(planRef, {...plan, nextStagePage: pageIndex + 1});
          return true; // Children/counters and receipt originally committed atomically.
        }
        if (plan.phase !== "planning" || parent.fanout.phase !== "planning" || !await acceptedPlan(tx, parentId, parent, plan)) return false;
        const stagedAtMs = now();
        if (!Number.isSafeInteger(stagedAtMs) || stagedAtMs <= 0 || stagedAtMs >= parent.expiresAtMs ||
            stagedAtMs < (plan.schemaVersion === 2 ? plan.acceptedAtMs : plan.snapshotAtMs) || (plan.schemaVersion === 1 && stagedAtMs - plan.snapshotAtMs > SNAPSHOT_AGE_MS)) return false;
        if (oldChildren.some((doc) => doc.exists && (doc.data().attempts !== 0 || doc.data().attemptToken || doc.data().attemptTokenHash || doc.data().messageId ||
            doc.data().startedAtMs != null || doc.data().completedAtMs != null || !["pending", "retry", "cancelled", "failed"].includes(doc.data().state)))) return false;
        for (const delivery of deliveries) tx.set(children.doc(delivery.id), {...delivery, schemaVersion: 1, parentId, generation,
          sourceRevision: parent.sourceRevision, envelopeHash: parent.fanout.envelopeHash, state: "pending", attempts: 0, availableAtMs: stagedAtMs});
        tx.set(pageRef, {schemaVersion: 1, parentId, generation, pageIndex, hash: pageHash, ids: deliveries.map((r) => r.id)});
        tx.set(planRef, {...plan, stagedPages: plan.stagedPages + 1, stagedRecipients: plan.stagedRecipients + deliveries.length,
          ...(plan.schemaVersion === 2 ? {nextStagePage: plan.nextStagePage === pageIndex ? pageIndex + 1 : plan.nextStagePage} : {})});
        return true;
      });
    },
    async sealPlan({parentId, generation}) {
      if (!validID(parentId)) return false;
      return db.runTransaction(async (tx) => {
        const ref = parents.doc(parentId), parent = (await tx.get(ref)).data();
        if (!binding(parentId, parent, generation)) return false;
        const planRef = plans.doc(parent.fanout.planId), [manifest, article, legacy] = await Promise.all([tx.get(planRef), ...sourceReads(tx, parent)]);
        const plan = manifest.data();
        if (!planBinding(parentId, parent, generation, plan)) return false;
        const accepted = await acceptedPlan(tx, parentId, parent, plan);
        if (plan.schemaVersion === 2 && !accepted) return false;
        if (parent.fanout.phase === "ready" && plan.phase === "ready") return true;
        const sealedAtMs = now();
        if (parent.fanout.phase !== "planning" || plan.phase !== "planning" || plan.stagedPages !== plan.expected.length || plan.stagedRecipients !== plan.total ||
            !accepted || !Number.isSafeInteger(sealedAtMs) || sealedAtMs <= 0 || parent.expiresAtMs <= sealedAtMs ||
            sealedAtMs < (plan.schemaVersion === 2 ? plan.acceptedAtMs : plan.snapshotAtMs) || (plan.schemaVersion === 1 && sealedAtMs - plan.snapshotAtMs > SNAPSHOT_AGE_MS) ||
            legacy.exists || !matches(parent, article.data())) return false;
        tx.set(planRef, {...plan, phase: "ready", ...(plan.schemaVersion === 2 ? {nextStagePage: plan.expected.length} : {}), sealedAtMs});
        tx.set(ref, {...parent, fanout: {...parent.fanout, phase: "ready"}});
        return true;
      });
    },
    async recoverPlan({parentId, generation, maximumPages = 10}) {
      if (!validID(parentId) || !Number.isSafeInteger(generation) || generation <= 0 || !Number.isInteger(maximumPages) || maximumPages < 1 || maximumPages > 100) return {status: "blocked", reason: "invalid_request"};
      let stagedPages = 0, nextPage = 0, totalPages = 0;
      for (let step = 0; step <= maximumPages; step++) {
        const current = await db.runTransaction(async (tx) => {
          const parent = (await tx.get(parents.doc(parentId))).data();
          if (!binding(parentId, parent, generation) || !["planning", "ready"].includes(parent.fanout.phase)) return {reason: "stale_parent"};
          const plan = (await tx.get(plans.doc(parent.fanout.planId))).data();
          if (!planBinding(parentId, parent, generation, plan) || plan.schemaVersion !== 2) return {reason: "unproven_frozen_plan"};
          const root = (await tx.get(inputRoots.doc(plan.frozenRootId))).data();
          if (!acceptedInput(plan.frozenRootId, root, parentId, parent, plan, now())) return {reason: "invalid_frozen_input"};
          if (parent.fanout.phase === "ready" && plan.phase === "ready") return {ready: true, plan};
          if (parent.fanout.phase !== "planning" || plan.phase !== "planning") return {reason: "phase_mismatch"};
          if (plan.nextStagePage === plan.expected.length) return {seal: true, plan};
          const page = (await tx.get(inputPages.doc(inputPageID(plan.frozenRootId, plan.nextStagePage)))).data();
          if (!validPage(plan.frozenRootId, root, page, plan.nextStagePage)) return {reason: "invalid_frozen_page"};
          return {plan, page};
        });
        if (current.reason) return {status: "blocked", reason: current.reason, stagedPages, nextPage, totalPages};
        nextPage = current.plan.nextStagePage;totalPages = current.plan.expected.length;
        if (current.ready) return {status: "ready", stagedPages, nextPage, totalPages};
        if (current.seal) {
          const sealed = await store.sealPlan({parentId, generation});
          return {status: sealed ? "ready" : "blocked", ...(sealed ? {} : {reason: "seal_rejected"}), stagedPages, nextPage, totalPages};
        }
        if (step === maximumPages) return {status: "planning", stagedPages, nextPage, totalPages};
        if (!await store.stagePage({parentId, generation, pageIndex: nextPage, deliveries: current.page.deliveries})) return {status: "blocked", reason: "stage_rejected", stagedPages, nextPage, totalPages};
        stagedPages++;
      }
    },
    async beginDelivery({parentId, generation, deliveryId}) {
      if (!validID(parentId) || !/^device-[a-f\d]{64}$/.test(deliveryId || "")) return null;
      return db.runTransaction(async (tx) => {
        const ref = parents.doc(parentId), childRef = children.doc(deliveryId);
        const [parentSnap, childSnap] = await Promise.all([tx.get(ref), tx.get(childRef)]), parent = parentSnap.data(), child = childSnap.data();
        if (!childBinding(parentId, parent, generation, child, deliveryId) || parent.fanout.phase !== "ready" ||
            !["pending", "retry"].includes(child.state) || child.availableAtMs > now()) return null;
        const [registration, article, legacy] = await Promise.all([tx.get(db.collection(INSTALLATIONS).doc(child.installationId)), ...sourceReads(tx, parent)]);
        const finish = (state, code) => {tx.set(childRef, {...child, state, code, availableAtMs: TERMINAL});return null;};
        if (parent.expiresAtMs <= now() || legacy.exists || !matches(parent, article.data())) return finish("cancelled", legacy.exists ? "legacy_handled" : parent.expiresAtMs <= now() ? "expired" : "source_changed");
        const decision = resolvePendingDelivery({...child, ...parent.fanout.event, id: deliveryId, eventId: parentId}, registration.data()?.active, {now: now()});
        if (decision.status === "cancel") return finish("cancelled", decision.reason);
        if (decision.status !== "ready") {
          const failures = (child.validationFailures || 0) + 1;
          tx.set(childRef, {...child, validationFailures: failures, state: failures >= maximumAttempts ? "failed" : "retry",
            code: "registration_unverified", availableAtMs: failures >= maximumAttempts ? TERMINAL : Math.min(parent.expiresAtMs, now() + 60000)});return null;
        }
        if (child.attempts > 0 && child.attemptTokenHash !== decision.tokenHash) return finish("uncertain", "retry_target_changed");
        if (child.attempts >= maximumAttempts) return finish("failed", "attempts_exhausted");
        if ((parent.transportNotBeforeMs || 0) > now()) {
          tx.set(childRef, {...child, state: "retry", code: "project_cooldown", availableAtMs: Math.min(parent.expiresAtMs, parent.transportNotBeforeMs)});return null;
        }
        const attemptToken = randomUUID(), next = {...child, attemptRegistrationRevision: decision.registrationRevision,
          state: "sending", attempts: child.attempts + 1, attemptTokenHash: decision.tokenHash, attemptToken, startedAtMs: now(),
          leaseExpiresAtMs: now() + leaseMs, availableAtMs: now() + leaseMs};
        let message;
        try {message = makeDeviceMessage({...parent, id: parentId}, next, decision.token);} catch {return finish("failed", "invalid_payload");}
        tx.set(childRef, next);
        // Atomically fence source refresh. Avoid a write hotspot after the first attempt.
        if (parent.transportStartedAtMs == null) tx.set(ref, {...parent, transportStartedAtMs: now()});
        return {attemptToken, message, leaseExpiresAtMs: next.leaseExpiresAtMs}; // Private transport values; never persist/log the raw token.
      });
    },
    async recordDelivery({parentId, generation, deliveryId, attemptToken, receipt}) {
      if (!validID(parentId) || !/^device-[a-f\d]{64}$/.test(deliveryId || "")) return false;
      return db.runTransaction(async (tx) => {
        const ref = parents.doc(parentId), childRef = children.doc(deliveryId), [parentSnap, childSnap] = await Promise.all([tx.get(ref), tx.get(childRef)]);
        const parent = parentSnap.data(), child = childSnap.data();
        if (!childBinding(parentId, parent, generation, child, deliveryId) || child.state !== "sending" || child.attemptToken !== attemptToken || child.leaseExpiresAtMs <= now()) return false;
        const ack = typeof receipt?.messageId === "string" && /^projects\/[a-zA-Z0-9-]+\/messages\/[a-zA-Z0-9%:_.~\/-]+$/.test(receipt.messageId) && receipt.messageId.length < 1000;
        const outcome = ack ? {state: "sent", messageId: receipt.messageId} : receipt?.error ? classifySendError(receipt.error) : {state: "uncertain", code: "missing_receipt"};
        if (receipt?.error?.code === "messaging/registration-token-not-registered") {outcome.state = "failed";outcome.code = "token_rejected";}
        if (outcome.state === "retry" && child.attempts >= maximumAttempts) outcome.state = "failed";
        const notBefore = outcome.state === "retry" ? Math.min(parent.expiresAtMs, now() + retryDelay(deliveryId, child.attempts, receipt.error, now())) : TERMINAL;
        tx.set(childRef, {...child, ...outcome, completedAtMs: now(), leaseExpiresAtMs: 0, availableAtMs: notBefore});
        if (outcome.state === "retry" && outcome.code === "rate_limited" && notBefore > (parent.transportNotBeforeMs || 0)) {
          tx.set(ref, {...parent, transportNotBeforeMs: notBefore});
        }
        return true;
      });
    },
    async recoverDelivery({parentId, generation, deliveryId}) {
      if (!validID(parentId) || !/^device-[a-f\d]{64}$/.test(deliveryId || "")) return false;
      return db.runTransaction(async (tx) => {
        const ref = children.doc(deliveryId), [parentSnap, childSnap] = await Promise.all([tx.get(parents.doc(parentId)), tx.get(ref)]);
        const parent = parentSnap.data(), child = childSnap.data();
        if (!childBinding(parentId, parent, generation, child, deliveryId) || child.state !== "sending" || child.leaseExpiresAtMs > now()) return false;
        tx.set(ref, {...child, state: "uncertain", code: "worker_expired", leaseExpiresAtMs: 0, availableAtMs: TERMINAL});return true;
      });
    },
    async summarizePage({parentId, generation, pageIndex}) {
      if (!validID(parentId) || !Number.isInteger(pageIndex) || pageIndex < 0) return {status: "incomplete"};
      return db.runTransaction(async (tx) => {
        const parent = (await tx.get(parents.doc(parentId))).data();
        if (!binding(parentId, parent, generation) || parent.fanout.phase !== "ready") return {status: "stale"};
        const [manifest, receipt] = await Promise.all([tx.get(plans.doc(parent.fanout.planId)), tx.get(pages.doc(pageID(parent.fanout.planId, pageIndex)))]);
        const plan = manifest.data(), page = receipt.data(), expected = plan?.expected?.[pageIndex];
        if (plan?.phase !== "ready" || !expected || page?.hash !== expected.hash || page.ids?.length !== expected.count || page.ids.length > PAGE_SIZE ||
            page.ids.some((id) => !/^device-[a-f\d]{64}$/.test(id))) return {status: "incomplete"};
        const rows = (await Promise.all(page.ids.map((id) => tx.get(children.doc(id))))).map((doc) => doc.data());
        const counts = {pending: 0, retry: 0, sending: 0, sent: 0, failed: 0, uncertain: 0, cancelled: 0};
        if (rows.some((row, i) => !childBinding(parentId, parent, generation, row, page.ids[i]) || !Object.hasOwn(counts, row.state)) ||
            pageDigest(rows) !== expected.hash) return {status: "incomplete"};
        for (const row of rows) counts[row.state]++;
        return {status: "complete", total: rows.length, counts}; // Complete page accounting, not all-device delivery.
      });
    },
  };
  return store;
}
async function runRecipientDelivery({store, parentId, generation, deliveryId, send, validate}) {
  // Service orchestration must additionally prove fresh canonical slug uniqueness before beginning.
  if (typeof validate !== "function" || !await validate({parentId, generation, deliveryId})) return {status: "skipped"};
  const attempt = await store.beginDelivery({parentId, generation, deliveryId});
  if (!attempt) return {status: "skipped"};
  let receipt;
  try {receipt = {messageId: await withSendDeadline(() => send(attempt.message))};} catch (error) {receipt = {error};}
  const recorded = await store.recordDelivery({parentId, generation, deliveryId, attemptToken: attempt.attemptToken, receipt});
  return {status: recorded ? "recorded" : "stale"};
}
module.exports = {COLLECTION, PLANS, PAGES, createRecipientFanoutStore, runRecipientDelivery};
