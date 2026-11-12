import { expect, test } from "@playwright/test";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

const event = (value: { type: string; [key: string]: unknown }) =>
  `event: ${value.type}\ndata: ${JSON.stringify(value)}\n\n`;

test.beforeEach(async ({ page }) => {
  await page.goto("/tests/anthropic.html");
  await page.waitForFunction(() => window.anthropicTests !== undefined);
});

test("Anthropic text arrives before completion and tools survive the bindings", async ({
  page,
}) => {
  let release!: () => void;
  const remaining = new Promise<void>((resolve) => {
    release = resolve;
  });
  const requests: { apiKey?: string; browserOptIn?: string; body: string }[] =
    [];
  const server = createServer(async (request, response) => {
    response.setHeader("Access-Control-Allow-Origin", "*");
    response.setHeader(
      "Access-Control-Allow-Headers",
      "x-api-key, anthropic-version, content-type, anthropic-dangerous-direct-browser-access",
    );
    response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (request.method === "OPTIONS") {
      response.writeHead(204).end();
      return;
    }
    if (request.url === "/models") {
      response.setHeader("Content-Type", "application/json");
      response.end('{"data":[{"id":"z"},{"id":"a"}]}');
      return;
    }
    if (request.url !== "/messages") {
      response.writeHead(404).end();
      return;
    }
    let body = "";
    for await (const bytes of request) body += bytes.toString();
    requests.push({
      apiKey: request.headers["x-api-key"] as string,
      browserOptIn: request.headers[
        "anthropic-dangerous-direct-browser-access"
      ] as string,
      body,
    });
    response.setHeader("Content-Type", "text/event-stream");
    response.write(
      event({
        type: "content_block_delta",
        index: 0,
        delta: { type: "text_delta", text: "Hello" },
      }),
    );
    await remaining;
    response.write(
      event({
        type: "content_block_start",
        index: 1,
        content_block: {
          type: "tool_use",
          id: "call-weather",
          name: "weather",
        },
      }),
    );
    response.write(
      event({
        type: "content_block_delta",
        index: 1,
        delta: {
          type: "input_json_delta",
          partial_json: '{"city":"Copenhagen"}',
        },
      }),
    );
    response.write(event({ type: "content_block_stop", index: 1 }));
    response.write(
      event({ type: "message_delta", delta: { stop_reason: "tool_use" } }),
    );
    response.end(event({ type: "message_stop" }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const running = page.evaluate(
      (base) => window.anthropicTests.run(base),
      `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    );
    await page.waitForFunction(() => window.anthropicText === "Hello");
    release();
    const result = await running;
    expect(result.models).toEqual(["a", "z"]);
    expect(result.content).toEqual(["Hello"]);
    expect(result.calls).toEqual([
      {
        id: "call-weather",
        kind: "function",
        name: "weather",
        arguments: '{"city":"Copenhagen"}',
      },
    ]);
    expect(result.finished).toBe(true);
    expect(result.failure).toBeUndefined();
    expect(requests).toHaveLength(1);
    expect(requests[0].apiKey).toBe("test-token");
    expect(requests[0].browserOptIn).toBe("true");
    const body = JSON.parse(requests[0].body);
    expect(body.cache_control).toEqual({ type: "ephemeral" });
    expect(body.tools[0].name).toBe("weather");
    expect(body.messages[0].content).toBe("hello");
  } finally {
    release();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

for (const streamed of [false, true]) {
  test(`Anthropic failures remain typed (${streamed ? "SSE" : "HTTP"})`, async ({
    page,
  }) => {
    await page.route("**/anthropic-test/**", async (route) => {
      if (route.request().url().endsWith("/models")) {
        await route.fulfill({ json: { data: [{ id: "test" }] } });
      } else if (streamed) {
        await route.fulfill({
          contentType: "text/event-stream",
          body: event({
            type: "error",
            error: { type: "overloaded_error", message: "busy" },
          }),
        });
      } else {
        await route.fulfill({
          status: 429,
          json: {
            error: { type: "rate_limit_error", message: "limited" },
          },
        });
      }
    });
    const result = await page.evaluate(() =>
      window.anthropicTests.run(`${location.origin}/anthropic-test`),
    );
    expect(result.failure).toBe("Http");
    expect(result.finished).toBe(false);
  });
}
