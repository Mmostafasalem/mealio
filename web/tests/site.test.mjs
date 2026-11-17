// The landing site must keep the pages App Store review opens: the privacy policy and support.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const legal = JSON.parse(readFileSync(new URL("../content/legal.json", import.meta.url), "utf8"));

test("the privacy policy and support text are present", () => {
  assert.ok(typeof legal.privacy === "string" && legal.privacy.length > 500);
  assert.ok(typeof legal.support === "string" && legal.support.length > 100);
});

test("the privacy, support and landing pages exist", () => {
  for (const page of ["../app/page.tsx", "../app/privacy/page.tsx", "../app/support/page.tsx"]) {
    assert.ok(existsSync(new URL(page, import.meta.url)), page);
  }
});

test("the old web app is gone", () => {
  for (const page of ["../app/chat", "../app/plan", "../app/setup", "../app/shop", "../app/api"]) {
    assert.ok(!existsSync(new URL(page, import.meta.url)), page);
  }
});
