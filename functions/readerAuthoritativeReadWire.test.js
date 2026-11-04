"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const fixture = require("./fixtures/reader-authoritative-read-wire-v1.json");
const {
  validateReaderMembershipReadRequest, validateReaderResourceReadRequest,
  validateReaderMembershipReadResponse, validateReaderResourceReadResponse,
} = require("./readerMutation");
const requestValidator = (kind) => kind === "membership" ? validateReaderMembershipReadRequest : validateReaderResourceReadRequest;
const responseValidator = (kind) => kind === "membership" ? validateReaderMembershipReadResponse : validateReaderResourceReadResponse;

test("native/server authoritative read fixture is v1", () => assert.equal(fixture.fixtureVersion, 1));
for (const [kind, vectors] of [["membership", fixture.membershipVectors], ["resource", fixture.resourceVectors]]) {
  for (const vector of vectors) {
    test(`shared ${kind} read: ${vector.name}`, () => {
      assert.deepEqual(requestValidator(kind)(vector.request), vector.request);
      assert.deepEqual(responseValidator(kind)(vector.response, vector.request), vector.response);
    });
  }
}
for (const vector of fixture.invalidRequests) {
  test(`shared invalid read request: ${vector.name}`, () => assert.throws(() => requestValidator(vector.kind)(vector.request)));
}
for (const vector of fixture.invalidResponses) {
  test(`shared invalid read response: ${vector.name}`, () => assert.throws(() => responseValidator(vector.kind)(vector.response, vector.request)));
}
