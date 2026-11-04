// One existing canonical slug document fences normal and maintenance producers.
// No delete/recreate, processing takeover or retry of unknown paid outcomes.
const {randomUUID} = require("node:crypto");
const noEffect = job => ["no_article", "empty", "deferred_quota"].includes(job?.status) && job.result === job.status;
const normalIdentity = job => JSON.stringify([job?.slug, job?.articleId, job?.name || "", job?.createdAt || null]);
function createNarrationOwnership({db, token = randomUUID}) {
  const ref = slug => {
    if (typeof slug !== "string" || !/^[a-z0-9]+(?:-+[a-z0-9]+)*$/.test(slug)) throw new Error("Canonical slug required");
    return db.collection("narration_queue").doc(slug);
  };
  return {
    async enqueue(payload) {
      return db.runTransaction(async tx => {
        const r = ref(payload.slug), current = await tx.get(r);
        if (current.exists) return {queued: false, reason: current.data()?.offlineMaintenanceReservation ? "maintenance_owned" : "existing_job_requires_readback"};
        tx.create(r, payload);return {queued: true, reason: "pending"};
      });
    },
    async claimNormal(slug, original) {
      const r = ref(slug), claim = token();
      const owns = job => job?.status === "processing" && job.narrationClaim === claim &&
        !job.offlineMaintenanceReservation && normalIdentity(job) === normalIdentity(original);
      const accepted = await db.runTransaction(async tx => {
        const current = await tx.get(r), job = current.data();
        if (!current.exists || job?.status !== "pending" || job.offlineMaintenance || job.offlineMaintenanceReservation ||
            normalIdentity(job) !== normalIdentity(original)) return false;
        tx.set(r, {status: "processing", narrationClaim: claim}, {merge: true});return true;
      });
      if (!accepted) return null;
      return {
        async assertCurrent() {const current = await r.get();if (!current.exists || !owns(current.data())) throw new Error("Original narration claim changed");},
        async assertFinished() {
          const current = await r.get(), job = current.data();
          if (!current.exists || !job || ["pending", "processing"].includes(job.status) || job.narrationClaim !== claim ||
              job.offlineMaintenanceReservation || normalIdentity(job) !== normalIdentity(original)) throw new Error("Finished narration ownership changed");
        },
        async finish(fields) {return db.runTransaction(async tx => {
          const current = await tx.get(r);if (!current.exists || !owns(current.data())) return false;
          tx.set(r, fields, {merge: true});return true;
        });},
      };
    },
    async reserveCreate(work) {
      return db.runTransaction(async tx => {
        const r = ref(work.source.articleSlug), current = await tx.get(r), job = current.data();
        if (current.exists && job.offlineMaintenanceReservation === work.key && job.status === "offline_reserved" &&
            job.slug === work.source.articleSlug && job.articleId === work.source.articleId) return;
        if (current.exists && !noEffect(job)) throw new Error("Existing canonical narration claim prevents maintenance");
        const marker = {slug: work.source.articleSlug, articleId: work.source.articleId,
          status: "offline_reserved", offlineMaintenanceReservation: work.key};
        if (current.exists) tx.set(r, marker, {merge: true});else tx.create(r, marker);
      });
    },
    async assertCreate(work) {
      const current = await ref(work.source.articleSlug).get(), job = current.data();
      if (!current.exists || job.status !== "offline_reserved" || job.offlineMaintenanceReservation !== work.key ||
          job.slug !== work.source.articleSlug || job.articleId !== work.source.articleId) throw new Error("Original canonical maintenance reservation changed");
    },
  };
}
module.exports = {createNarrationOwnership};
