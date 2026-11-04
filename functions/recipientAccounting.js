// SDK-free, known-parent accounting only. No send, parent write, topic fallback, or service initialization.
const {randomUUID} = require("node:crypto");
const {COLLECTION: PARENTS, valid: validParent} = require("./pushOutbox");
const {COLLECTION: CHILDREN, PLANS, PAGES} = require("./recipientFanout");
const {INPUT_ROOTS, INPUT_PAGES, digest, compact, pageDigest, validDescriptor, validExpected, validRoot, validPage, inputID, inputPageID, acceptedInput} = require("./recipientFrozenInput");
const CHECKPOINTS = "article_push_recipient_accounting", PROOFS = "article_push_recipient_accounting_pages";
const STATES = Object.freeze(["pending", "retry", "sending", "sent", "failed", "uncertain", "cancelled"]);
const TERMINAL_STATES = new Set(["sent", "failed", "uncertain", "cancelled"]), TERMINAL = Number.MAX_SAFE_INTEGER;
const timeValue = (v) => Number.isSafeInteger(v) && v > 0;
const parentID = (v) => typeof v === "string" && /^article-[a-f\d]{64}$/.test(v);
const hex = (v) => typeof v === "string" && /^[a-f\d]{64}$/.test(v);
const opaque = (v) => typeof v === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(v);
const exact = (v, keys) => !!v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === keys.length && keys.every((key) => Object.hasOwn(v, key));
const emptyCounts = () => Object.fromEntries(STATES.map((state) => [state, 0]));
const sum = (counts) => STATES.reduce((total, state) => total + counts[state], 0);
const validCounts = (counts) => exact(counts, STATES) && STATES.every((state) => Number.isSafeInteger(counts[state]) && counts[state] >= 0 && counts[state] <= 100000);
const addCounts = (left, right) => Object.fromEntries(STATES.map((state) => [state, left[state] + right[state]]));
const planID = (parentId, generation) => `${parentId}-${generation}`;
const proofID = (record, pageIndex) => `${planID(record.parentId, record.generation)}-${record.passId}-${pageIndex}`;
const genesis = (bindingHash, passId) => digest(["recipient-accounting-v1", bindingHash, passId]);
function bindingOf(parentId, generation, parent, plan, root, time) {
  if (!parentID(parentId) || !Number.isSafeInteger(generation) || generation < 1 || !validParent(parentId, parent) || parent.deliveryMode !== "installations-v1" ||
      parent.fanout?.generation !== generation || parent.fanout.planId !== planID(parentId, generation) || parent.fanout.phase !== "ready" ||
      parent.fanout.sourceRevision !== parent.sourceRevision || parent.fanout.envelopeHash !== digest(parent.envelope) || !hex(parent.fanout.planHash) ||
      plan?.schemaVersion !== 2 || plan.parentId !== parentId || plan.generation !== generation || plan.phase !== "ready" || plan.planHash !== parent.fanout.planHash ||
      !inputID(plan.frozenRootId) || !validExpected(plan.expected, plan.total) || plan.stagedPages !== plan.expected.length || plan.stagedRecipients !== plan.total ||
      plan.nextStagePage !== plan.expected.length || !timeValue(plan.sealedAtMs) || plan.sealedAtMs < plan.acceptedAtMs || !timeValue(time) || time < plan.sealedAtMs ||
      !validRoot(plan.frozenRootId, root) || !acceptedInput(plan.frozenRootId, root, parentId, parent, plan, plan.acceptedAtMs) || time < plan.acceptedAtMs) return null;
  return {parentId, generation, planId: parent.fanout.planId, frozenRootId: plan.frozenRootId, planHash: plan.planHash,
    bindingHash: digest([parentId, generation, parent.sourceRevision, parent.fanout.envelopeHash, parent.fanout.event, plan.frozenRootId,
      plan.planHash, plan.expected, plan.total, plan.snapshotHash, plan.snapshotAtMs, plan.acceptedAtMs, plan.expiresAtMs, plan.sealedAtMs]),
    total: plan.total, totalPages: plan.expected.length};
}
const recordKeys = ["schemaVersion", "parentId", "generation", "planId", "frozenRootId", "planHash", "bindingHash", "total", "totalPages", "phase", "passId", "nextPage",
  "counts", "terminalPages", "lastProofHash", "auditPage", "auditCounts", "auditTerminalPages", "auditProofHash", "startedAtMs", "updatedAtMs", "completedAtMs", "revision", "token", "expiresAtMs"];
function validRecord(record, binding) {
  return exact(record, recordKeys) && record.schemaVersion === 1 && Object.keys(binding).every((key) => record[key] === binding[key]) &&
    ["active", "complete"].includes(record.phase) && opaque(record.passId) && Number.isSafeInteger(record.nextPage) && record.nextPage >= 0 && record.nextPage <= record.totalPages &&
    validCounts(record.counts) && sum(record.counts) <= record.total && Number.isSafeInteger(record.terminalPages) && record.terminalPages >= 0 && record.terminalPages <= record.nextPage &&
    hex(record.lastProofHash) && Number.isSafeInteger(record.auditPage) && record.auditPage >= 0 && record.auditPage <= record.nextPage &&
    (record.auditPage === 0 || record.nextPage === record.totalPages) && validCounts(record.auditCounts) && sum(record.auditCounts) <= sum(record.counts) &&
    Number.isSafeInteger(record.auditTerminalPages) && record.auditTerminalPages >= 0 && record.auditTerminalPages <= record.auditPage && hex(record.auditProofHash) &&
    (record.auditPage !== 0 || sum(record.auditCounts) === 0 && record.auditTerminalPages === 0 && record.auditProofHash === genesis(record.bindingHash, record.passId)) && timeValue(record.startedAtMs) && timeValue(record.updatedAtMs) && record.updatedAtMs >= record.startedAtMs &&
    Number.isSafeInteger(record.revision) && record.revision > 0 && Number.isSafeInteger(record.expiresAtMs) && record.expiresAtMs >= 0 &&
    (record.token === null ? record.expiresAtMs === 0 : opaque(record.token) && record.phase === "active" && record.expiresAtMs > record.updatedAtMs) &&
    (record.nextPage !== 0 || sum(record.counts) === 0 && record.terminalPages === 0 && record.lastProofHash === genesis(record.bindingHash, record.passId)) &&
    (record.phase === "active" ? record.completedAtMs === null : record.nextPage === record.totalPages && sum(record.counts) === record.total &&
      record.auditPage === record.totalPages && digest(record.auditCounts) === digest(record.counts) && record.auditTerminalPages === record.terminalPages && record.auditProofHash === record.lastProofHash &&
      record.token === null && timeValue(record.completedAtMs) && record.completedAtMs === record.updatedAtMs);
}
const proofCore = (proof) => Object.fromEntries(Object.entries(proof).filter(([key]) => key !== "proofHash"));
const proofKeys = ["schemaVersion", "parentId", "generation", "passId", "pageIndex", "planHash", "frozenRootId", "pageHash", "count", "counts", "terminal", "outcomeHash",
  "previousProofHash", "cumulativeCounts", "cumulativeTerminalPages", "observedAtMs", "proofHash"];
function validProof(proof, record, plan, index) {
  const expected = plan.expected[index];
  return expected && exact(proof, proofKeys) && proof.schemaVersion === 1 && proof.parentId === record.parentId && proof.generation === record.generation &&
    proof.passId === record.passId && proof.pageIndex === index && proof.planHash === record.planHash && proof.frozenRootId === record.frozenRootId &&
    proof.pageHash === expected.hash && proof.count === expected.count && validCounts(proof.counts) && sum(proof.counts) === proof.count &&
    typeof proof.terminal === "boolean" && proof.terminal === (proof.counts.pending + proof.counts.retry + proof.counts.sending === 0) && hex(proof.outcomeHash) && hex(proof.previousProofHash) &&
    validCounts(proof.cumulativeCounts) && sum(proof.cumulativeCounts) === plan.expected.slice(0, index + 1).reduce((count, row) => count + row.count, 0) &&
    STATES.every((state) => proof.cumulativeCounts[state] >= proof.counts[state]) && Number.isInteger(proof.cumulativeTerminalPages) &&
    proof.cumulativeTerminalPages >= (proof.terminal ? 1 : 0) && proof.cumulativeTerminalPages <= index + 1 &&
    timeValue(proof.observedAtMs) && proof.observedAtMs >= record.startedAtMs && proof.observedAtMs <= record.updatedAtMs && proof.proofHash === digest(proofCore(proof));
}
function validReceipt(receipt, record, pageIndex, deliveries, proof) {
  return exact(receipt, ["schemaVersion", "parentId", "generation", "pageIndex", "hash", "ids"]) && receipt.schemaVersion === 1 && receipt.parentId === record.parentId &&
    receipt.generation === record.generation && receipt.pageIndex === pageIndex && receipt.hash === proof.hash && Array.isArray(receipt.ids) && receipt.ids.length === proof.count &&
    digest(receipt.ids) === digest(deliveries.map((row) => row.id));
}
function childObservation(child, delivery, binding, sourceRevision, envelopeHash, observedAtMs) {
  if (!child || child.schemaVersion !== 1 || child.id !== delivery.id || child.parentId !== binding.parentId || child.generation !== binding.generation ||
      child.sourceRevision !== sourceRevision || child.envelopeHash !== envelopeHash || !validDescriptor(compact(child), binding.parentId) || digest(compact(child)) !== digest(delivery) ||
      !STATES.includes(child.state) || !Number.isSafeInteger(child.attempts) || child.attempts < 0 || !Number.isSafeInteger(child.availableAtMs) || child.availableAtMs < 0) return null;
  const childTimes = [child?.startedAtMs, child?.completedAtMs].filter((value) => value !== undefined);
  if (childTimes.some((value) => !timeValue(value) || value > observedAtMs) ||
      child.attemptToken !== undefined && !opaque(child.attemptToken) || child.attemptTokenHash !== undefined && !hex(child.attemptTokenHash) ||
      child.attemptRegistrationRevision !== undefined && (!Number.isSafeInteger(child.attemptRegistrationRevision) || child.attemptRegistrationRevision < 1) ||
      child.leaseExpiresAtMs !== undefined && (!Number.isSafeInteger(child.leaseExpiresAtMs) || child.leaseExpiresAtMs < 0)) return null;
  const attemptFields = [child.attemptToken, child.attemptTokenHash, child.attemptRegistrationRevision, child.startedAtMs, child.completedAtMs, child.messageId];
  if (child.attempts === 0 && (attemptFields.some((value) => value !== undefined) || ["sending", "sent", "uncertain"].includes(child.state)) ||
      child.attempts > 0 && (!opaque(child.attemptToken) || !hex(child.attemptTokenHash) || !Number.isSafeInteger(child.attemptRegistrationRevision) || child.attemptRegistrationRevision < 1 || !timeValue(child.startedAtMs) || child.state === "pending") ||
      child.state === "sending" && (!timeValue(child.leaseExpiresAtMs) || child.leaseExpiresAtMs <= child.startedAtMs || child.availableAtMs !== child.leaseExpiresAtMs) ||
      child.state !== "sent" && child.messageId !== undefined) return null;
  // A state string alone is insufficient evidence of a provider acknowledgement.
  if (child.state === "sent" && (child.attempts < 1 || !opaque(child.attemptToken) || !hex(child.attemptTokenHash) || !Number.isSafeInteger(child.attemptRegistrationRevision) || child.attemptRegistrationRevision < 1 ||
      !timeValue(child.startedAtMs) || !timeValue(child.completedAtMs) || child.completedAtMs < child.startedAtMs || child.completedAtMs > observedAtMs || child.leaseExpiresAtMs !== 0 || child.availableAtMs !== TERMINAL ||
      typeof child.messageId !== "string" || !/^projects\/[a-zA-Z0-9-]+\/messages\/[a-zA-Z0-9%:_.~\/-]+$/.test(child.messageId) || child.messageId.length >= 1000)) return null;
  if (TERMINAL_STATES.has(child.state) && child.availableAtMs !== TERMINAL) return null;
  // Hash only controlled accounting fields; raw provider IDs/errors/tokens never enter the accounting store.
  return [child.id, child.state, child.attempts, child.state === "sent" ? digest(child.messageId) : null,
    child.attemptTokenHash || null, child.startedAtMs ?? null, child.completedAtMs ?? null, child.leaseExpiresAtMs ?? null, child.availableAtMs];
}
function summary(record) {
  const terminal = record.terminalPages === record.totalPages && record.counts.pending + record.counts.retry + record.counts.sending === 0;
  return {parentId: record.parentId, generation: record.generation, passId: record.passId,
    result: record.phase !== "complete" ? "incomplete" : record.total === 0 ? "empty_audience" : terminal ? "terminal_accounted" : "windowed_accounted",
    total: record.total, totalPages: record.totalPages, observedPages: record.nextPage, counts: {...record.counts}, providerAcknowledged: record.counts.sent,
    outstanding: record.counts.pending + record.counts.retry + record.counts.sending, startedAtMs: record.startedAtMs, completedAtMs: record.completedAtMs,
    consistency: record.phase === "complete" && terminal ? "terminal" : "windowed", historical: true};
}
function ticket(record) {
  const {parentId, generation, passId, nextPage, auditPage, revision, token, expiresAtMs} = record;
  return {parentId, generation, passId, nextPage, auditPage, revision, token, expiresAtMs};
}
const ticketKeys = ["parentId", "generation", "passId", "nextPage", "auditPage", "revision", "token", "expiresAtMs"];
function validTicket(lease) {
  return exact(lease, ticketKeys) && parentID(lease.parentId) && Number.isSafeInteger(lease.generation) && lease.generation > 0 && opaque(lease.passId) &&
    Number.isSafeInteger(lease.nextPage) && lease.nextPage >= 0 && lease.nextPage <= 1000 && Number.isSafeInteger(lease.auditPage) && lease.auditPage >= 0 && lease.auditPage <= lease.nextPage && Number.isSafeInteger(lease.revision) && lease.revision > 0 && opaque(lease.token) && timeValue(lease.expiresAtMs);
}
const owns = (record, lease, time) => record.phase === "active" && record.token !== null && record.updatedAtMs <= time && record.expiresAtMs > time &&
  ticketKeys.every((key) => record[key] === lease[key]);
function unavailable() {const error = new Error("Recipient accounting unavailable");error.code = "accounting/unavailable";return error;}
function createRecipientAccountingStore({db, now = Date.now, leaseMs = 120000, makeID = randomUUID}) {
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function" || typeof now !== "function" || typeof makeID !== "function" ||
      !Number.isSafeInteger(leaseMs) || leaseMs <= 0 || leaseMs > 3600000) throw new Error("Invalid recipient accounting configuration");
  const parents = db.collection(PARENTS), plans = db.collection(PLANS), roots = db.collection(INPUT_ROOTS), inputs = db.collection(INPUT_PAGES), receipts = db.collection(PAGES),
    children = db.collection(CHILDREN), checkpoints = db.collection(CHECKPOINTS), proofs = db.collection(PROOFS);
  const clock = () => {const time = now();if (!timeValue(time) || !Number.isSafeInteger(time + leaseMs)) throw unavailable();return time;};
  const identity = () => {const id = makeID();if (!opaque(id)) throw unavailable();return id;};
  const transaction = async (callback) => {try {return await db.runTransaction(callback);} catch {throw unavailable();}};
  const load = async (tx, parentId, generation) => {
    const parent = (await tx.get(parents.doc(parentId))).data();
    if (!validParent(parentId, parent) || parent.fanout?.planId !== planID(parentId, generation)) return null;
    const plan = (await tx.get(plans.doc(planID(parentId, generation)))).data();
    if (!inputID(plan?.frozenRootId)) return null;
    const root = (await tx.get(roots.doc(plan.frozenRootId))).data();return {parent, plan, root};
  };
  const priorProof = async (tx, record, plan) => {
    if (record.nextPage > 0) {
      const proof = (await tx.get(proofs.doc(proofID(record, record.nextPage - 1)))).data();
      if (!validProof(proof, record, plan, record.nextPage - 1) || proof.proofHash !== record.lastProofHash ||
          digest(proof.cumulativeCounts) !== digest(record.counts) || proof.cumulativeTerminalPages !== record.terminalPages ||
          record.nextPage === 1 && proof.previousProofHash !== genesis(record.bindingHash, record.passId)) return false;
    }
    if (record.auditPage > 0) {
      const proof = (await tx.get(proofs.doc(proofID(record, record.auditPage - 1)))).data();
      if (!validProof(proof, record, plan, record.auditPage - 1) || proof.proofHash !== record.auditProofHash ||
          digest(proof.cumulativeCounts) !== digest(record.auditCounts) || proof.cumulativeTerminalPages !== record.auditTerminalPages) return false;
    }
    return true;
  };
  const ownTicket = (value) => {try {return structuredClone(value);} catch {return null;}};
  const request = (parentId, generation) => parentID(parentId) && Number.isSafeInteger(generation) && generation > 0;
  return {
    async claim({parentId, generation}) {
      if (!request(parentId, generation)) return {status: "blocked", reason: "invalid_request"};
      return transaction(async (tx) => {
        const state = await load(tx, parentId, generation);if (!state) return {status: "blocked", reason: "binding"};
        const ref = checkpoints.doc(planID(parentId, generation)), snapshot = await tx.get(ref), old = snapshot.data();
        const before = bindingOf(parentId, generation, state.parent, state.plan, state.root, clock());
        if (!before) return {status: "blocked", reason: "binding"};
        if (snapshot.exists !== true && snapshot.exists !== false || !snapshot.exists && old !== undefined || snapshot.exists && !validRecord(old, before)) return {status: "blocked", reason: "corrupt_checkpoint"};
        if (old && !await priorProof(tx, old, state.plan)) return {status: "blocked", reason: "corrupt_proof"};
        const time = clock(), binding = bindingOf(parentId, generation, state.parent, state.plan, state.root, time);
        if (!binding) return {status: "blocked", reason: "binding"};
        if (old?.updatedAtMs > time) return {status: "blocked", reason: "clock_regressed"};
        if (old?.token && old.expiresAtMs > time) return {status: "busy"};
        if (old?.revision === Number.MAX_SAFE_INTEGER) return {status: "blocked", reason: "revision_exhausted"};
        const fresh = !old || old.phase === "complete", token = identity(), passId = fresh ? identity() : old.passId;
        if (token === passId || token === old?.token || fresh && passId === old?.passId) return {status: "blocked", reason: "identity_collision"};
        const record = {schemaVersion: 1, ...binding, phase: "active", passId, nextPage: fresh ? 0 : old.nextPage,
          counts: fresh ? emptyCounts() : old.counts, terminalPages: fresh ? 0 : old.terminalPages, lastProofHash: fresh ? genesis(binding.bindingHash, passId) : old.lastProofHash,
          auditPage: fresh ? 0 : old.auditPage, auditCounts: fresh ? emptyCounts() : old.auditCounts, auditTerminalPages: fresh ? 0 : old.auditTerminalPages,
          auditProofHash: fresh ? genesis(binding.bindingHash, passId) : old.auditProofHash, startedAtMs: fresh ? time : old.startedAtMs, updatedAtMs: time, completedAtMs: null, revision: (old?.revision || 0) + 1, token, expiresAtMs: time + leaseMs};
        tx.set(ref, record);return {status: "claimed", lease: ticket(record)};
      });
    },
    async step({lease}) {
      lease = ownTicket(lease);if (!validTicket(lease)) return {status: "blocked", reason: "invalid_lease"};
      return transaction(async (tx) => {
        const state = await load(tx, lease.parentId, lease.generation);if (!state) return {status: "blocked", reason: "binding"};
        const ref = checkpoints.doc(planID(lease.parentId, lease.generation)), record = (await tx.get(ref)).data();
        const binding = bindingOf(lease.parentId, lease.generation, state.parent, state.plan, state.root, clock());
        if (!binding || !validRecord(record, binding)) return {status: "blocked", reason: "corrupt_checkpoint"};
        if (!await priorProof(tx, record, state.plan)) return {status: "blocked", reason: "corrupt_proof"};
        let page, receipt, rows, pageProofRef, auditProofs;
        if (record.nextPage < binding.totalPages) {
          pageProofRef = proofs.doc(proofID(record, record.nextPage));
          const [inputSnap, receiptSnap, oldProofSnap] = await Promise.all([tx.get(inputs.doc(inputPageID(binding.frozenRootId, record.nextPage))),
            tx.get(receipts.doc(`${binding.planId}-${record.nextPage}`)), tx.get(pageProofRef)]);
          page = inputSnap.data();receipt = receiptSnap.data();
          if (!validPage(binding.frozenRootId, state.root, page, record.nextPage) || !validReceipt(receipt, record, record.nextPage, page.deliveries, state.plan.expected[record.nextPage]) || oldProofSnap.exists) return {status: "blocked", reason: "corrupt_page"};
          rows = (await Promise.all(page.deliveries.map((delivery) => tx.get(children.doc(delivery.id))))).map((snap) => snap.data());
        } else if (record.auditPage < binding.totalPages) {
          // Audit the complete durable chain in bounded groups; no missing early proof may hide behind its final hash.
          const indexes = Array.from({length: Math.min(100, binding.totalPages - record.auditPage)}, (_, i) => record.auditPage + i);
          auditProofs = (await Promise.all(indexes.map((index) => tx.get(proofs.doc(proofID(record, index)))))).map((snap) => snap.data());
        }
        // No awaits after this clock: the same value guards the lease and every persisted observation.
        const time = clock();
        if (!bindingOf(lease.parentId, lease.generation, state.parent, state.plan, state.root, time)) return {status: "blocked", reason: "binding"};
        if (!owns(record, lease, time)) return {status: "stale"};
        if (record.revision === Number.MAX_SAFE_INTEGER) return {status: "blocked", reason: "revision_exhausted"};
        let newProof;
        let next = {...record, updatedAtMs: time, revision: record.revision + 1, expiresAtMs: time + leaseMs};
        if (page) {
          const observations = rows.map((child, i) => childObservation(child, page.deliveries[i], binding, state.parent.sourceRevision, state.parent.fanout.envelopeHash, time));
          if (observations.some((row) => row === null) || pageDigest(rows) !== state.plan.expected[record.nextPage].hash) return {status: "blocked", reason: "corrupt_child"};
          const counts = emptyCounts();for (const child of rows) counts[child.state]++;
          const terminal = counts.pending + counts.retry + counts.sending === 0, cumulativeCounts = addCounts(record.counts, counts);
          const proof = {schemaVersion: 1, parentId: record.parentId, generation: record.generation, passId: record.passId, pageIndex: record.nextPage,
            planHash: binding.planHash, frozenRootId: binding.frozenRootId, pageHash: page.hash, count: rows.length, counts, terminal, outcomeHash: digest(observations),
            previousProofHash: record.lastProofHash, cumulativeCounts, cumulativeTerminalPages: record.terminalPages + (terminal ? 1 : 0), observedAtMs: time};
          proof.proofHash = digest(proofCore(proof));
          next = {...next, nextPage: record.nextPage + 1, counts: cumulativeCounts, terminalPages: proof.cumulativeTerminalPages, lastProofHash: proof.proofHash};
          newProof = proof;
        }
        if (auditProofs) {
          let counts = record.auditCounts, terminalPages = record.auditTerminalPages, previous = record.auditProofHash;
          for (let i = 0; i < auditProofs.length; i++) {
            const proof = auditProofs[i], index = record.auditPage + i;
            if (!validProof(proof, record, state.plan, index) || proof.previousProofHash !== previous) return {status: "blocked", reason: "corrupt_chain"};
            counts = addCounts(counts, proof.counts);terminalPages += proof.terminal ? 1 : 0;
            if (digest(counts) !== digest(proof.cumulativeCounts) || terminalPages !== proof.cumulativeTerminalPages) return {status: "blocked", reason: "corrupt_chain"};
            previous = proof.proofHash;
          }
          next = {...next, auditPage: record.auditPage + auditProofs.length, auditCounts: counts, auditTerminalPages: terminalPages, auditProofHash: previous};
        }
        if (next.nextPage === binding.totalPages && next.auditPage === binding.totalPages) {
          if (sum(next.counts) !== binding.total || digest(next.counts) !== digest(next.auditCounts) || next.terminalPages !== next.auditTerminalPages || next.lastProofHash !== next.auditProofHash) return {status: "blocked", reason: "incomplete_counts"};
          next = {...next, phase: "complete", token: null, expiresAtMs: 0, completedAtMs: time};
          tx.set(ref, next);return {status: "completed", summary: summary(next)};
        }
        if (newProof) tx.set(pageProofRef, newProof);
        tx.set(ref, next);return {status: "advanced", lease: ticket(next)};
      });
    },
    async release({lease}) {
      lease = ownTicket(lease);if (!validTicket(lease)) return false;
      return transaction(async (tx) => {
        const state = await load(tx, lease.parentId, lease.generation);if (!state) return false;
        const ref = checkpoints.doc(planID(lease.parentId, lease.generation)), record = (await tx.get(ref)).data();
        const binding = bindingOf(lease.parentId, lease.generation, state.parent, state.plan, state.root, clock());
        if (!binding || !validRecord(record, binding) || !await priorProof(tx, record, state.plan)) return false;
        const time = clock();if (!bindingOf(lease.parentId, lease.generation, state.parent, state.plan, state.root, time) || !owns(record, lease, time) || record.revision === Number.MAX_SAFE_INTEGER) return false;
        tx.set(ref, {...record, token: null, expiresAtMs: 0, revision: record.revision + 1, updatedAtMs: time});return true;
      });
    },
    async read({parentId, generation}) {
      if (!request(parentId, generation)) return {status: "blocked", reason: "invalid_request"};
      return transaction(async (tx) => {
        const state = await load(tx, parentId, generation);if (!state) return {status: "blocked", reason: "binding"};
        const snapshot = await tx.get(checkpoints.doc(planID(parentId, generation))), record = snapshot.data();
        const binding = bindingOf(parentId, generation, state.parent, state.plan, state.root, clock());
        if (!binding) return {status: "blocked", reason: "binding"};
        if (snapshot.exists === false && record === undefined) return {status: "missing"};
        if (!validRecord(record, binding) || !await priorProof(tx, record, state.plan)) return {status: "blocked", reason: "corrupt_checkpoint"};
        const time = clock();if (time < record.updatedAtMs || !bindingOf(parentId, generation, state.parent, state.plan, state.root, time)) return {status: "blocked", reason: "clock_regressed"};
        return {status: record.phase, summary: summary(record)}; // Historical observations, never a fresh all-device snapshot.
      });
    },
  };
}
async function runRecipientAccounting({store, parentId, generation, maximumSteps = 10, timeBudgetMs = 15000, now = Date.now}) {
  if (["claim", "step", "release"].some((key) => typeof store?.[key] !== "function") || typeof now !== "function" || !Number.isInteger(maximumSteps) || maximumSteps < 1 || maximumSteps > 1100 ||
      !Number.isSafeInteger(timeBudgetMs) || timeBudgetMs <= 0 || timeBudgetMs > 300000) throw new Error("Invalid recipient accounting configuration");
  let start;try {start = now();} catch {throw new Error("Invalid recipient accounting clock");}if (!timeValue(start) || !Number.isSafeInteger(start + timeBudgetMs)) throw new Error("Invalid recipient accounting clock");
  let lease, steps = 0, last = start, completed = false, result;
  const permitsStart = () => {const time = now();if (!timeValue(time) || time < last) throw unavailable();last = time;return time < start + timeBudgetMs;};
  try {
    const claimed = await store.claim({parentId, generation});
    if (claimed?.status === "busy") return {status: "busy", steps};
    if (claimed?.status === "blocked") return {status: "blocked", reason: "checkpoint", steps};
    if (claimed?.status !== "claimed" || !validTicket(claimed.lease)) throw unavailable();lease = claimed.lease;
    while (steps < maximumSteps && permitsStart()) {
      const step = await store.step({lease});
      if (step?.status === "completed") {completed = true;steps++;result = {status: "completed", steps, summary: step.summary};break;}
      if (step?.status === "stale") {result = {status: "stale", steps};break;}
      if (step?.status === "blocked") {result = {status: "blocked", reason: "accounting", steps};break;}
      if (step?.status !== "advanced" || !validTicket(step.lease)) throw unavailable();lease = step.lease;steps++;
    }
    if (!result) result = {status: "yielded", reason: steps >= maximumSteps ? "step_budget" : "time_budget", steps};
  } catch {result = {status: "failed", reason: "accounting", steps};}
  if (lease && !completed) {try {await store.release({lease});} catch {return {status: "failed", reason: "release", steps};}}
  return result;
}
module.exports = {CHECKPOINTS, PROOFS, STATES, createRecipientAccountingStore, runRecipientAccounting};
