const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createPublishedCMSReader} = require("./offlineAudioLiveSource");
const {contentRevision} = require("./webflowCatalog");

const collectionID = "a".repeat(24), id = n => n.toString(16).padStart(24, "0");
const copy = value => structuredClone(value);
function article(n = 1, extra = {}) {
  return {id: id(n), isDraft: false, isArchived: false, createdOn: "2026-10-01T08:00:00Z", lastPublished: "2026-11-01T09:00:00Z",
    fieldData: {slug: `story-${n}`, name: `Actual published title ${n}`, content: "<p>Ægte publiceret tekst.</p>",
      intro: "Publiceret intro", subtitle: null, stjerne: 5, nested: {labels: ["en", "to"], untouched: true}}, ...extra};
}
const page = (items, total = items.length, offset = 0, limit = 100) => ({items, pagination: {total, offset, limit}});
const response = (data, status = 200) => ({ok: status >= 200 && status < 300, status, json: async () => copy(data)});
function fixture(reply) {
  const requests = [];let keyReads = 0;
  const reader = createPublishedCMSReader({collectionID, apiKey: () => {keyReads++;return "fixture-existing-reader";},
    fetch: async (url, options) => {
      requests.push({url, options});return typeof reply === "function" ? reply(url, options, requests.length) : response(reply);
    }});
  return {reader, requests, keyReads: () => keyReads};
}

test("all requests the documented live collection path with exact raw pagination offsets", async () => {
  const first = Array.from({length: 100}, (_, i) => article(i + 1)), second = Array.from({length: 5}, (_, i) => article(i + 101));
  const f = fixture((url, options, request) => {
    const u = new URL(url);assert.equal(u.origin, "https://api.webflow.com");
    assert.equal(u.pathname, `/v2/collections/${collectionID}/items/live`);assert.equal(u.searchParams.get("limit"), "100");
    assert.equal(u.searchParams.has("live"), false);assert.equal(u.searchParams.get("offset"), request === 1 ? "0" : "100");
    assert.equal(options.method, "GET");assert.equal(options.headers.Authorization, "Bearer fixture-existing-reader");
    assert.ok(options.signal instanceof AbortSignal);assert.equal(options.signal.aborted, false);
    return response(page(request === 1 ? first : second, 105, request === 1 ? 0 : 100));
  });
  const result = await f.reader.all();assert.equal(result.length, 105);assert.equal(f.requests.length, 2);assert.equal(f.keyReads(), 2);
  assert.equal(result[104].id, id(105));
});
test("short live pages advance by raw count rather than assuming limit-sized pages", async () => {
  const f = fixture((url, options, count) => response(page([article(count)], 2, count - 1)));
  const result = await f.reader.all();assert.deepEqual(result.map(a => a.id), [id(1), id(2)]);
  assert.deepEqual(f.requests.map(r => new URL(r.url).searchParams.get("offset")), ["0", "1"]);
});
test("one uses documented item/live path and binds the exact requested canonical identity", async () => {
  const f = fixture(article());const value = await f.reader.one(id(1));
  assert.equal(new URL(f.requests[0].url).pathname, `/v2/collections/${collectionID}/items/${id(1)}/live`);
  assert.equal(new URL(f.requests[0].url).search, "");assert.equal(value.id, id(1));
  const wrong = fixture(article(2));assert.equal(await wrong.reader.one(id(1)), null);
});
test("actual live fieldData, creation/publication values and original item remain unchanged while canonical revision is derived", async () => {
  const original = article(1, {contentRevision: "stale-mirror-hash", externalField: {preserve: [1, 2]}}), before = copy(original);
  const f = fixture(original);const value = await f.reader.one(id(1));
  assert.equal(value.contentRevision, contentRevision(before));assert.deepEqual(value.fieldData, before.fieldData);
  assert.equal(value.createdOn, before.createdOn);assert.equal(value.lastPublished, before.lastPublished);
  assert.deepEqual(value.externalField, before.externalField);assert.deepEqual(original, before);
  assert.equal(value.fieldData.content, "<p>Ægte publiceret tekst.</p>");
});
test("all derives the same source revision as one without reshaping nested CMS content", async () => {
  const a = article(), all = fixture(page([a])), one = fixture(a);
  assert.deepEqual((await all.reader.all())[0], await one.reader.one(id(1)));
});
test("draft/staged, archived and unconfirmed publication states fail closed for one", async () => {
  for (const change of [{isDraft: true}, {isDraft: undefined}, {isArchived: true}, {lastPublished: null},
    {lastPublished: ""}, {lastPublished: "not-a-date"}, {lastPublished: 1}]) {
    const f = fixture(article(1, change));assert.equal(await f.reader.one(id(1)), null);assert.equal(f.requests.length, 1);
  }
});
test("all excludes denied rows but advances pagination using all raw rows", async () => {
  const f = fixture((url, options, count) => count === 1 ? response(page([
    article(1, {isDraft: true}), article(2, {isArchived: true}), article(3, {lastPublished: null})], 4, 0)) : response(page([article(4)], 4, 3)));
  assert.deepEqual((await f.reader.all()).map(a => a.id), [id(4)]);assert.equal(f.requests.length, 2);
  assert.equal(new URL(f.requests[1].url).searchParams.get("offset"), "3");
});
test("removed item404 is absence for one but collection404 is not an authoritative empty inventory", async () => {
  const one = fixture(() => response({private: "not-to-be-exposed"}, 404));assert.equal(await one.reader.one(id(1)), null);
  const all = fixture(() => response({}, 404));await assert.rejects(all.reader.all(), /404/);assert.equal(all.requests.length, 1);
});
test("explicit empty live catalog is authoritative only with a valid zero envelope", async () => {
  const f = fixture(page([]));assert.deepEqual(await f.reader.all(), []);assert.equal(f.requests.length, 1);
});
test("negative/oversized/fractional/missing totals cannot claim complete live inventory", async () => {
  for (const payload of [page([], -1), page([], 10001), page([], 1.5), {items: [], pagination: {offset: 0}}, {}, {items: []}]) {
    const f = fixture(payload);await assert.rejects(f.reader.all());assert.equal(f.requests.length, 1);
  }
});
test("a page exceeding announced total is rejected instead of silently considered complete", async () => {
  for (const payload of [page([article()], 0), page([article(1), article(2)], 1)]) {
    const f = fixture(payload);await assert.rejects(f.reader.all());assert.equal(f.requests.length, 1);
  }
});
test("live total cannot change between pages in either direction", async () => {
  for (const second of [page([article(2)], 1, 1), page([article(2)], 3, 1)]) {
    const f = fixture((url, options, count) => response(count === 1 ? page([article()], 2, 0) : second));
    await assert.rejects(f.reader.all());assert.equal(f.requests.length, 2);
  }
});
test("wrong raw offsets, pages over limit and premature empty pages reject complete publication proof", async () => {
  for (const payload of [page([article()], 1, 5), page(Array.from({length: 101}, (_, i) => article(i + 1)), 101), page([], 1)]) {
    const f = fixture(payload);await assert.rejects(f.reader.all());assert.equal(f.requests.length, 1);
  }
  const f = fixture((url, options, count) => response(count === 1 ? page([article()], 2, 0) : page([], 2, 1)));
  await assert.rejects(f.reader.all());assert.equal(f.requests.length, 2);
});
test("duplicate live IDs including filtered drafts are never silently deduplicated", async () => {
  const f = fixture((url, options, count) => response(count === 1 ? page([article(1, {isDraft: true})], 2, 0) : page([article(1)], 2, 1)));
  await assert.rejects(f.reader.all(), /Ambiguous/);assert.equal(f.requests.length, 2);
});
test("invalid live canonical IDs fail before the reader returns a successful complete snapshot", async () => {
  for (const value of ["../outside", "not-canonical", "", 42, undefined]) {
    const f = fixture(page([article(1, {id: value})]));await assert.rejects(f.reader.all());assert.equal(f.requests.length, 1);
  }
});
test("missing/malformed fieldData cannot become paid-source publication authority", async () => {
  for (const fieldData of [undefined, null, [], "not-an-object"]) {
    const all = fixture(page([article(1, {fieldData})]));await assert.rejects(all.reader.all());
    const one = fixture(article(1, {fieldData}));assert.equal(await one.reader.one(id(1)), null);
  }
});
test("429, server errors and denied access stop once without retry or exposing server bodies", async () => {
  for (const status of [401, 403, 429, 500, 503]) {
    for (const method of ["all", "one"]) {
      const f = fixture(() => ({ok: false, status, json: () => assert.fail("must not read sensitive error body")}));
      await assert.rejects(method === "one" ? f.reader.one(id(1)) : f.reader.all(), error =>
        error.message.includes(String(status)) && !error.message.includes("fixture-existing-reader"));
      assert.equal(f.requests.length, 1);
    }
  }
});
test("second-page429 rejects the full scan instead of yielding a partial source set or retrying", async () => {
  const f = fixture((url, options, count) => count === 1 ? response(page([article()], 2, 0)) : response({}, 429));
  await assert.rejects(f.reader.all(), /429/);assert.equal(f.requests.length, 2);
});
test("transport and JSON failures are propagated with no additional request", async () => {
  for (const reply of [async () => {throw new Error("fixture transport failed");}, async () => ({ok: true, status: 200, json: async () => {throw new Error("fixture malformed JSON");}})]) {
    const f = fixture(reply);await assert.rejects(f.reader.all());assert.equal(f.requests.length, 1);
  }
});
test("invalid request identities/configuration never reach the transport", async () => {
  assert.throws(() => createPublishedCMSReader({fetch: async () => {}, apiKey: () => "fixture", collectionID: "../invalid"}));
  assert.throws(() => createPublishedCMSReader({apiKey: () => "fixture", collectionID}));
  const f = fixture(article());for (const value of ["../id", "invalid", id(1) + "/live", 1, null]) await assert.rejects(f.reader.one(value));
  assert.equal(f.requests.length, 0);
});
