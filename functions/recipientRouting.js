// SDK-free per-installation routing. No topic fallback or assumed migration coverage.
const {createHash} = require("node:crypto");
const hash = (value) => createHash("sha256").update(value).digest("hex");
const installationID = (value) => typeof value === "string" && /^[a-f\d]{8}-[a-f\d]{4}-[1-8][a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/.test(value);
function preferences(value) {
  if (!value || !["all", "categories", "off"].includes(value.articles) || typeof value.podcasts !== "boolean" || !Array.isArray(value.categoryIds) || value.categoryIds.length > 100 ||
      value.categoryIds.some((id) => typeof id !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(id))) throw new Error("Invalid recipient preferences");
  const categoryIds = [...new Set(value.categoryIds)].sort();
  if (value.articles === "categories" ? !categoryIds.length : categoryIds.length) throw new Error("Inconsistent recipient preferences");
  return {articles: value.articles, categoryIds, podcasts: value.podcasts};
}
function eventDescriptor(event) {
  if (!event || typeof event.id !== "string" || !/^[a-zA-Z0-9_-]{1,160}$/.test(event.id) || !["article", "podcast"].includes(event.family) ||
      !/^[a-f\d]{24}$/i.test(event.articleId || "") || !/^cms-sha256-v1:[a-f\d]{64}$/.test(event.sourceRevision || "") ||
      !Array.isArray(event.categoryIds) || event.categoryIds.length > 100 || event.categoryIds.some((id) => typeof id !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(id))) throw new Error("Invalid recipient event");
  return {...event, categoryIds: [...new Set(event.categoryIds)].sort()};
}
function matchesEvent(event, pref) {
  return event.family === "podcast" ? pref.podcasts : pref.articles === "all" ||
    (pref.articles === "categories" && pref.categoryIds.some((id) => event.categoryIds.includes(id)));
}
function activeRegistration(row, now) {
  if (!row || row.schemaVersion !== 1 || !installationID(row.installationId) || row.state !== "active" ||
      !Number.isSafeInteger(row.revision) || row.revision < 1 || !Number.isSafeInteger(row.ownerEpoch) || row.ownerEpoch < 1 ||
      !(row.ownerUID === null || (typeof row.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(row.ownerUID))) ||
      typeof row.token !== "string" || row.token.length < 20 || row.token.length > 4096 || /\s/.test(row.token) ||
      row.proof?.tokenHash !== hash(row.token) || !/^[a-f\d]{64}$/.test(row.proof?.challengeId || "") ||
      !Number.isSafeInteger(row.proof.confirmedAtMs) || row.proof.confirmedAtMs < 1 || row.proof.confirmedAtMs > now + 300000 ||
      typeof row.proof.appId !== "string" || !row.proof.appId) return false;
  try {preferences(row.preferences);return true;} catch {return false;}
}
function inactiveRegistration(row) {
  if (!row || row.schemaVersion !== 1 || !installationID(row.installationId) || !["disabled", "revoked"].includes(row.state) ||
      !Number.isSafeInteger(row.revision) || row.revision < 1 || !Number.isSafeInteger(row.ownerEpoch) || row.ownerEpoch < 1 ||
      !(row.ownerUID === null || (typeof row.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(row.ownerUID)))) return false;
  try {preferences(row.preferences);return true;} catch {return false;}
}
function deliveryID(eventId, id) {return "device-" + hash(JSON.stringify([eventId, id]));}
function registrationDigest(row) {
  return hash(JSON.stringify([row.installationId, row.revision, row.ownerEpoch, row.ownerUID, row.state,
    row.proof?.tokenHash || null, row.proof?.challengeId || null, row.proof?.appId || null, row.proof?.confirmedAtMs || null, row.preferences ? preferences(row.preferences) : null]));
}
function planRecipients({event: input, registrations, coverage, now = Date.now(), maximumInstallations = 100000}) {
  const event = eventDescriptor(input), issues = [];
  const blocked = (code) => ({status: "blocked", issues: [code], deliveries: [], summary: {eligible: 0, delivered: 0}});
  if (!Array.isArray(registrations) || registrations.length > maximumInstallations) return blocked("registry_snapshot_unbounded");
  if (coverage?.schemaVersion !== 1 || coverage.mode !== "device-registry-v1" || coverage.legacyTopicFanoutDisabled !== true ||
      coverage.legacyClientMigrationAccepted !== true || !/^[a-f\d]{64}$/.test(coverage.inventoryHash || "") ||
      !Number.isSafeInteger(coverage.snapshotAtMs) || coverage.snapshotAtMs > now || now - coverage.snapshotAtMs > 300000 ||
      !Array.isArray(coverage.expected) || coverage.expected.length > maximumInstallations) return blocked("migration_or_snapshot_unproven");
  const expected = new Map();
  for (const item of coverage.expected) {
    if (!item || !installationID(item.installationId) || expected.has(item.installationId) || !/^[a-f\d]{64}$/.test(item.digest || "")) return blocked("invalid_coverage_roster");
    expected.set(item.installationId, item.digest);
  }
  const devices = new Map(), tokens = new Map();
  for (const row of registrations) {
    if (!installationID(row?.installationId) || devices.has(row.installationId)) {issues.push("duplicate_or_invalid_installation");continue;}
    devices.set(row.installationId, row);
    try {if (expected.get(row.installationId) !== registrationDigest(row)) issues.push("registry_snapshot_changed");} catch {issues.push("invalid_registration");}
    if (row.state === "disabled" || row.state === "revoked") {
      if (!inactiveRegistration(row)) issues.push("unproven_optout");
      continue;
    }
    if (!activeRegistration(row, now)) {issues.push("unverified_registration");continue;}
    const tokenHash = row.proof.tokenHash;
    if (tokens.has(tokenHash)) issues.push("token_owned_by_multiple_installations");
    tokens.set(tokenHash, row.installationId);
  }
  if ([...expected.keys()].some((id) => !devices.has(id))) issues.push("missing_installation");
  if (devices.size !== expected.size) issues.push("registry_coverage_incomplete");
  if (issues.length) return {status: "blocked", issues: [...new Set(issues)].sort(), deliveries: [], summary: {eligible: 0, delivered: 0}};
  const deliveries = [...devices.values()].filter((row) => row.state === "active" && matchesEvent(event, preferences(row.preferences)))
    .sort((a, b) => a.installationId.localeCompare(b.installationId)).map((row) => ({
      id: deliveryID(event.id, row.installationId), eventId: event.id, articleId: event.articleId, sourceRevision: event.sourceRevision,
      family: event.family, categoryIds: event.categoryIds, installationId: row.installationId,
      ownerUID: row.ownerUID, ownerEpoch: row.ownerEpoch, registrationRevision: row.revision, tokenHash: row.proof.tokenHash,
    }));
  return {status: "ready", issues: [], deliveries, summary: {eligible: deliveries.length, delivered: 0, installations: devices.size}};
}
function resolvePendingDelivery(delivery, registration, {attemptStarted = false, now = Date.now()} = {}) {
  if (attemptStarted) return {status: "immutable", reason: "attempt_already_started"};
  if (inactiveRegistration(registration) && registration.installationId === delivery.installationId) return {status: "cancel", reason: "installation_disabled"};
  if (!activeRegistration(registration, now) || registration.installationId !== delivery.installationId) return {status: "defer", reason: "registration_unverified"};
  if (registration.ownerUID !== delivery.ownerUID || registration.ownerEpoch !== delivery.ownerEpoch) return {status: "cancel", reason: "account_changed"};
  const event = eventDescriptor({id: delivery.eventId, articleId: delivery.articleId, sourceRevision: delivery.sourceRevision, family: delivery.family, categoryIds: delivery.categoryIds});
  if (!matchesEvent(event, preferences(registration.preferences))) return {status: "cancel", reason: "preferences_changed"};
  return {status: "ready", id: delivery.id, token: registration.token, tokenHash: registration.proof.tokenHash, registrationRevision: registration.revision};
}
module.exports = {hash, installationID, preferences, eventDescriptor, matchesEvent, activeRegistration, deliveryID, registrationDigest, planRecipients, resolvePendingDelivery};
