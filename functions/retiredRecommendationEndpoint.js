// Permanently retired reader endpoint. No payload parsing, provider work, or reactivation switch.
const RETIRED_RECOMMENDATION_OPTIONS = Object.freeze({
  invoker: "private",
  cors: false,
  secrets: Object.freeze([]),
  memory: "128MiB",
  timeoutSeconds: 10,
  minInstances: 0,
  maxInstances: 1,
  concurrency: 1,
});
const RETIREMENT_RESPONSE = Object.freeze({status: "unavailable", code: "recommendation_reasons_retired"});
function retiredRecommendationEndpoint(request, response) {
  const isPost = request.method === "POST";
  response.set("Cache-Control", "no-store");
  response.set("Content-Type", "application/json; charset=utf-8");
  if (!isPost) response.set("Allow", "POST");
  response.status(isPost ? 410 : 405).json(RETIREMENT_RESPONSE);
}
module.exports = {RETIRED_RECOMMENDATION_OPTIONS, retiredRecommendationEndpoint};
