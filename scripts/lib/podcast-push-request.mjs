// Shared SDK-free caller protocol. No environment/credential reads at import time.
import podcastPolicy from '../../functions/podcastPush.js';
const {normalizePodcastRequest, podcastID, resendContext} = podcastPolicy;
export {resendContext};
export async function postPodcastNotification({payload, endpoint, secret, transport = fetch}) {
  const request = normalizePodcastRequest(payload);
  if (typeof secret !== 'string' || !secret.trim()) throw new Error('Rotated podcast notify secret required');
  const response = await transport(endpoint, {method: 'POST', signal: AbortSignal.timeout(30000),
    headers: {'Content-Type': 'application/json', 'X-Apropos-Podcast-Secret': secret},
    body: JSON.stringify({articleSlug: request.slug, kind: request.kind, sourceArticleId: request.sourceArticleId,
      sourceContentRevision: request.sourceContentRevision, audioURL: request.audioURL,
      resendId: request.resendId, resendReason: request.resendReason})});
  if (!response.ok) throw new Error(`Podcast handoff unconfirmed: HTTP ${response.status}`);
  const receipt = await response.json();
  const expected = podcastID(request.sourceArticleId, request.kind, request.resendId);
  if (receipt.status === 'queued' && receipt.outbox_id === expected &&
      ['pending', 'retry', 'processing', 'sent', 'suppressed', 'needs_review', 'failed'].includes(receipt.state)) {
    return {queued: true, outboxId: expected, state: receipt.state};
  }
  if (receipt.status === 'skipped' && receipt.reason === 'legacy_handled') return {sent: false, reason: 'legacy_handled'};
  throw new Error('Podcast handoff missing a bound durable receipt');
}
