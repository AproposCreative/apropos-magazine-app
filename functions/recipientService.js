// Server composition only: no Firebase initialization, credentials, environment defaults or Cloud exports.
const {createRecipientRegistry} = require("./recipientRegistry");
const {createRecipientAdmissionStore} = require("./recipientAdmission");
const {createRecipientHttpHandler, createFirebaseRecipientIdentityVerifier} = require("./recipientEndpoint");
const {withSendDeadline} = require("./pushOutbox");
const headers = {"cache-control": "no-store", pragma: "no-cache", "x-content-type-options": "nosniff", "content-type": "application/json; charset=utf-8"};
function createRecipientHttpService({db, appCheck, auth, messaging, policy, now = Date.now, trustedIngressKey, admitIngress}) {
  if (!policy || typeof messaging?.send !== "function" || typeof trustedIngressKey !== "function" || typeof admitIngress !== "function") throw new Error("Missing recipient service configuration");
  const verifyIdentity = createFirebaseRecipientIdentityVerifier({appCheck, auth, now, projectId: policy.projectId,
    projectNumber: policy.projectNumber, allowedAppIds: policy.allowedAppIds});
  const store = createRecipientRegistry({db, now});
  const admission = createRecipientAdmissionStore({db, now, limits: policy.limits});
  const deliverChallenge = async (challenge) => {
    // No alert, sound or badge. A provider ack is not proof the challenge reached iOS.
    const messageId = await messaging.send({token: challenge.token, data: challenge.data, apns: {
      headers: {"apns-push-type": "background", "apns-priority": "5", "apns-expiration": "0", "apns-collapse-id": challenge.data.challenge_id},
      payload: {aps: {contentAvailable: true}},
    }});
    if (typeof messageId !== "string" || !/^projects\/[a-zA-Z0-9-]+\/messages\/[a-zA-Z0-9%:_.~\/-]+$/.test(messageId) || messageId.length >= 1000) throw new Error("Challenge acknowledgement unavailable");
  };
  const handler = (operation) => {
    const endpoint = createRecipientHttpHandler({operation, store, verifyIdentity, deliverChallenge, admitRequest: admission.admitRequest});
    return async (req, res) => {
      let result;
      try {
        // This resolver is server configuration. Never derive its trust from a body/query field
        // or accept arbitrary forwarding headers without an approved trusted-proxy policy.
        const key = trustedIngressKey(req);
        if (typeof key !== "string" || !/^[a-f\d]{64}$/.test(key)) throw new Error("Unverified ingress");
        result = await withSendDeadline(() => admitIngress({key, operation}), {timeoutMs: 5000});
      } catch {result = null;}
      if (result?.allowed !== true) {
        const throttled = result?.allowed === false && Number.isFinite(result.retryAfterMs) && result.retryAfterMs > 0;
        const responseHeaders = {...headers, ...(throttled ? {"retry-after": String(Math.max(1, Math.min(3600, Math.ceil(result.retryAfterMs / 1000))))} : {})};
        res.set(responseHeaders);return res.status(throttled ? 429 : 503).json({error: throttled ? "rate_limited" : "temporarily_unavailable", retryable: true});
      }
      return endpoint(req, res);
    };
  };
  return Object.freeze({register: handler("register"), confirm: handler("confirm")});
}
module.exports = {createRecipientHttpService};
