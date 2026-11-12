import { expect, test } from "@playwright/test";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

const catalog = { data: [{ id: "test" }] };
const delta = (value: object, finish: string | null = null) =>
  `data: ${JSON.stringify({ choices: [{ delta: value, finish_reason: finish }] })}\n\n`;

test.beforeEach(async ({ page }) => {
  await page.goto("/tests/eigin-relay.html");
  await page.waitForFunction(() => window.relayTests !== undefined);
});

test("missing relay configuration rejects provider construction", async ({
  page,
}) => {
  expect(
    await page.evaluate(() => window.relayTests.invalidConfiguration()),
  ).toBe(true);
});

test("discovery needs no wallet and an initial 402 switches wallets", async ({
  page,
}) => {
  const requests: { path: string; authorization?: string; key?: string }[] = [];
  await page.route("**/relay-test/v1/**", async (route) => {
    const request = route.request();
    const headers = request.headers();
    const path = new URL(request.url()).pathname;
    requests.push({
      path,
      authorization: headers.authorization,
      key: headers["x-eigin-key"],
    });
    if (path.endsWith("/models")) {
      await route.fulfill({ json: catalog });
    } else if (headers.authorization === "Bearer first") {
      await route.fulfill({ status: 402, body: "exhausted" });
    } else {
      await route.fulfill({
        contentType: "text/event-stream",
        body: delta({ content: "hello" }, "stop"),
      });
    }
  });
  const result = await page.evaluate(() =>
    window.relayTests.run(`${location.origin}/relay-test`),
  );
  expect(result.models).toEqual(["test"]);
  expect(result.discoverySelections).toBe(0);
  expect(result.exhausted).toEqual(["first"]);
  expect(result.selections).toBe(2);
  expect(result.content).toEqual(["hello"]);
  expect(result.finished).toBe(true);
  expect(result.failure).toBeUndefined();
  expect(requests).toEqual([
    {
      path: "/relay-test/v1/models",
      authorization: undefined,
      key: "relay-key",
    },
    {
      path: "/relay-test/v1/chat/completions",
      authorization: "Bearer first",
      key: "relay-key",
    },
    {
      path: "/relay-test/v1/chat/completions",
      authorization: "Bearer second",
      key: "relay-key",
    },
  ]);
});

test("text arrives before completion and streamed tool calls reach the caller", async ({
  page,
}) => {
  let release!: () => void;
  const remaining = new Promise<void>((resolve) => {
    release = resolve;
  });
  const requests: { authorization?: string; key?: string; body: string }[] = [];
  const server = createServer(async (request, response) => {
    response.setHeader("Access-Control-Allow-Origin", "*");
    response.setHeader(
      "Access-Control-Allow-Headers",
      "authorization, x-eigin-key, content-type",
    );
    response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (request.method === "OPTIONS") {
      response.writeHead(204).end();
      return;
    }
    if (request.url === "/v1/models") {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify(catalog));
      return;
    }
    if (request.url !== "/v1/chat/completions") {
      response.writeHead(404).end();
      return;
    }
    let body = "";
    for await (const bytes of request) body += bytes.toString();
    requests.push({
      authorization: request.headers.authorization,
      key: request.headers["x-eigin-key"] as string,
      body,
    });
    response.setHeader("Content-Type", "text/event-stream");
    response.write(delta({ content: "Hello" }));
    await remaining;
    response.write(delta({ content: " there" }));
    response.write(
      delta({
        tool_calls: [
          {
            index: 0,
            id: "call_weather",
            type: "function",
            function: { name: "weather", arguments: '{"city":' },
          },
        ],
      }),
    );
    response.write(
      delta({
        tool_calls: [{ index: 0, function: { arguments: '"Copenhagen"}' } }],
      }),
    );
    response.end(delta({}, "tool_calls"));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const running = page.evaluate((url) => window.relayTests.run(url), base);
    await page.waitForFunction(() => window.relayText === "Hello");
    release();
    const result = await running;
    expect(result.content.join("")).toBe("Hello there");
    expect(result.calls).toEqual([
      {
        id: "call_weather",
        kind: "function",
        name: "weather",
        arguments: '{"city":"Copenhagen"}',
      },
    ]);
    expect(result.finished).toBe(true);
    expect(result.failure).toBeUndefined();
    expect(requests).toHaveLength(1);
    expect(requests[0].authorization).toBe("Bearer first");
    expect(requests[0].key).toBe("relay-key");
    const body = JSON.parse(requests[0].body);
    expect(body.messages).toEqual([
      { role: "user", content: "Say hello and check the weather" },
    ]);
    expect(body.tools[0].function.name).toBe("weather");
    expect(body.stream).toBe(true);
  } finally {
    release();
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
});

for (const status of [403, 402]) {
  test(`HTTP ${status} reaches the caller without a successful completion`, async ({
    page,
  }) => {
    let attempts = 0;
    await page.route("**/relay-test/v1/**", async (route) => {
      if (route.request().url().endsWith("/models")) {
        await route.fulfill({ json: catalog });
      } else {
        attempts++;
        await route.fulfill({ status, body: "rejected" });
      }
    });
    const result = await page.evaluate(() =>
      window.relayTests.run(`${location.origin}/relay-test`),
    );
    expect(result.failure).toEqual(
      status === 402 ? { kind: "NoCredits" } : { kind: "Http", status },
    );
    expect(result.content).toEqual([]);
    expect(result.calls).toEqual([]);
    expect(result.finished).toBe(false);
    expect(result.exhausted).toEqual(status === 402 ? ["first", "second"] : []);
    expect(attempts).toBe(status === 402 ? 2 : 1);
  });
}
