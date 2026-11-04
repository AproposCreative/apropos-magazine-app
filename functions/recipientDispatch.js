// SDK-free bounded-start dispatcher. No trigger, live transport, or topic fallback.
const {runRecipientDelivery} = require("./recipientFanout");

const LANES = new Set(["deliver", "recover"]);
const validCursor = (cursor) => cursor && Number.isSafeInteger(cursor.availableAtMs) && cursor.availableAtMs >= 0 &&
  typeof cursor.id === "string" && cursor.id.length > 0 && cursor.id !== "." && cursor.id !== ".." && !cursor.id.includes("/") &&
  Buffer.byteLength(cursor.id) <= 1500 && Buffer.from(cursor.id, "utf8").toString("utf8") === cursor.id;
const compare = (a, b) => a.availableAtMs - b.availableAtMs || Buffer.compare(Buffer.from(a.id), Buffer.from(b.id));
const validCandidate = (value) => value && typeof value.parentId === "string" && /^article-[a-f\d]{64}$/.test(value.parentId) &&
  typeof value.deliveryId === "string" && /^device-[a-f\d]{64}$/.test(value.deliveryId) && Number.isSafeInteger(value.generation) && value.generation > 0;

/**
 * Invoke each lane independently with its own budget; delivery backlog must not
 * consume recovery's invocation. Row/time budgets bound work STARTS, not total
 * lifetime: injected query/validation/transaction awaits may be noncooperative.
 * The existing delivery runner bounds send observation; it cannot undo an SDK
 * side effect or prove device delivery. Never run this against unaccepted routing.
 */
async function runRecipientDispatchLane({dispatch, fanout, lane, send, validate, now = Date.now,
  maximumRows = 100, pageSize = 50, timeBudgetMs = 15000}) {
  const methods = ["claim", "discover", "assertCurrent", "advance", "complete", "release"];
  if (!LANES.has(lane) || methods.some((key) => typeof dispatch?.[key] !== "function") || typeof now !== "function" ||
      !Number.isInteger(maximumRows) || maximumRows < 1 || maximumRows > 1000 ||
      !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100 ||
      !Number.isSafeInteger(timeBudgetMs) || timeBudgetMs <= 0 || timeBudgetMs > 300000 ||
      (lane === "deliver" && (typeof send !== "function" || typeof validate !== "function" ||
        typeof fanout?.beginDelivery !== "function" || typeof fanout?.recordDelivery !== "function")) ||
      (lane === "recover" && typeof fanout?.recoverDelivery !== "function")) throw new Error("Invalid recipient dispatch configuration");

  const startedAtMs = now();
  if (!Number.isSafeInteger(startedAtMs) || startedAtMs < 0 || !Number.isSafeInteger(startedAtMs + timeBudgetMs)) {
    throw new Error("Invalid recipient dispatch clock");
  }
  const deadlineMs = startedAtMs + timeBudgetMs;
  const counts = {scanned: 0, attempted: 0, recorded: 0, recovered: 0, skipped: 0, checkpointed: 0};
  let lease, stopReason, fatalStage, stage = "claim", completed = false, lastClockMs = startedAtMs;
  const summary = (status, reason) => ({status, lane, ...counts, ...(reason ? {reason} : {})});
  const permitsStart = () => {
    const clock = now();
    if (!Number.isSafeInteger(clock) || clock < lastClockMs) throw new Error("Invalid recipient dispatch clock");
    lastClockMs = clock;
    if (clock >= deadlineMs) {stopReason = "time_budget";return false;}
    return true;
  };
  const current = async () => {
    stage = "ownership";
    try {
      if (stopReason || !permitsStart()) return false;
      const owned = await dispatch.assertCurrent({lease});
      if (typeof owned !== "boolean") throw new Error("Invalid dispatch ownership result");
      if (!owned) {stopReason = "ownership_lost";return false;}
      return permitsStart();
    } catch (error) {fatalStage = "ownership";throw error;}
  };
  const stopped = () => summary(stopReason === "ownership_lost" ? "lost" : "yielded", stopReason);
  let result;
  try {
    const claim = await dispatch.claim({lane});
    if (claim?.status === "busy") return summary("busy");
    if (claim?.status === "blocked") return summary("blocked", "checkpoint");
    if (claim?.status !== "claimed" || claim.lease?.lane !== lane || !Number.isSafeInteger(claim.lease.cutoffMs) ||
        claim.lease.cutoffMs < 0 || (claim.lease.cursor !== null && !validCursor(claim.lease.cursor))) throw new Error("Invalid dispatch claim");
    lease = claim.lease;
    while (true) {
      if (!await current()) {result = stopped();break;}
      const limit = Math.min(pageSize, maximumRows - counts.scanned);
      if (limit < 1) {result = summary("yielded", "row_budget");break;}
      stage = "discover";
      const page = await dispatch.discover({lease, limit});
      if (!await current()) {result = stopped();break;}
      stage = "page";
      if (page?.status !== "page" || !Array.isArray(page.rows) || page.rows.length > limit || typeof page.exhausted !== "boolean" ||
          (!page.rows.length && !page.exhausted)) throw new Error("Invalid dispatch page");
      let previous = lease.cursor;
      for (const row of page.rows) {
        if (!validCursor(row?.cursor) || row.cursor.availableAtMs > lease.cutoffMs || (previous && compare(row.cursor, previous) <= 0)) {
          throw new Error("Invalid dispatch page cursor");
        }
        previous = row.cursor;
      }
      for (const row of page.rows) {
        if (!await current()) break;
        counts.scanned++;
        const candidate = validCandidate(row.candidate) ? {parentId: row.candidate.parentId,
          generation: row.candidate.generation, deliveryId: row.candidate.deliveryId} : null;
        if (!candidate) {
          counts.skipped++;
        } else if (lane === "recover") {
          stage = "recover";
          const recovered = await fanout.recoverDelivery(candidate);
          if (typeof recovered !== "boolean") throw new Error("Invalid recipient recovery result");
          recovered ? counts.recovered++ : counts.skipped++;
        } else {
          let rowOpen = true, childDeadlineMs;
          try {
            const outcome = await runRecipientDelivery({...candidate,
              validate: async (identity) => {
                if (!await current()) return false;
                stage = "validate";
                const valid = await validate(identity);
                if (!await current()) return false;
                if (typeof valid !== "boolean") throw new Error("Invalid canonical validation result");
                return valid;
              },
              store: {
                beginDelivery: async (identity) => {
                  if (!await current()) return null;
                  stage = "begin";
                  const attempt = await fanout.beginDelivery(identity);
                  if (attempt) {
                    if (!Number.isSafeInteger(attempt.leaseExpiresAtMs) || attempt.leaseExpiresAtMs < 0) throw new Error("Invalid child attempt deadline");
                    childDeadlineMs = attempt.leaseExpiresAtMs;
                  }
                  // A committed child attempt is never refunded if the lane lease
                  // expires here. Recovery owns that conservative unknown outcome.
                  return await current() ? attempt : null;
                },
                recordDelivery: async (receipt) => {
                  // The child's original attempt token/lease remains authority
                  // even when dispatch ownership expired after an actual send.
                  stage = "record";
                  return fanout.recordDelivery(receipt);
                },
              },
              send: (message) => {
                // No async work may precede the actual send inside its observation
                // deadline. The last durable ownership check is post-begin above;
                // this synchronous fence also rejects a lease that expired before
                // the callback starts. Otherwise a late ownership read could start
                // transport after the send observer had already timed out.
                let allowed;
                try {allowed = rowOpen && !stopReason && permitsStart();} catch (error) {fatalStage = "ownership";throw error;}
                if (allowed && (!Number.isSafeInteger(lease.expiresAtMs) || lease.expiresAtMs <= lastClockMs || childDeadlineMs <= lastClockMs)) {
                  stopReason = "ownership_lost";allowed = false;
                }
                if (!allowed) throw new Error("Recipient dispatch start stopped");
                counts.attempted++;
                stage = "send";
                return send(message);
              },
            });
            if (outcome.status === "recorded") counts.recorded++;
            else if (outcome.status === "skipped") counts.skipped++;
            else if (outcome.status === "stale") {result = summary("failed", "receipt_not_recorded");break;}
            else throw new Error("Invalid recipient delivery outcome");
          } finally {rowOpen = false;}
          if (fatalStage) {result = summary("failed", fatalStage);break;}
        }
        if (!await current()) break;
        stage = "advance";
        const advanced = await dispatch.advance({lease, row});
        if (advanced?.status === "stale") {stopReason = "ownership_lost";break;}
        if (advanced?.status !== "advanced" || !advanced.lease) throw new Error("Invalid dispatch checkpoint result");
        lease = advanced.lease;
        counts.checkpointed++;
      }
      if (result) break;
      if (stopReason) {result = stopped();break;}
      if (page.exhausted) {
        if (!await current()) {result = stopped();break;}
        stage = "complete";
        const completion = await dispatch.complete({lease});
        if (completion?.status === "stale") {stopReason = "ownership_lost";result = stopped();break;}
        if (completion?.status !== "completed") throw new Error("Invalid dispatch completion result");
        completed = true;result = summary("completed");break;
      }
    }
  } catch {
    // Do not expose tokens, raw candidates, SDK errors, or private payloads.
    result = summary("failed", stage);
  }
  if (lease && !completed) {
    try {await dispatch.release({lease});} catch {result = summary("failed", "release");}
  }
  return result;
}

module.exports = {runRecipientDispatchLane};
