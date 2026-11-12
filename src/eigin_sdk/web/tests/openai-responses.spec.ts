import { expect, test } from "@playwright/test";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

const event = (value: object) => `data: ${JSON.stringify(value)}\n\n`;

test.beforeEach(async ({ page }) => {
  await page.goto("/tests/openai-responses.html");
  await page.waitForFunction(() => window.responsesTests !== undefined);
});

test("Responses text arrives before completion and tools survive the bindings", async ({
  page,
}) => {
  let release!: () => void;
  const remaining = new Promise<void>((resolve) => {
    release = resolve;
  });
  const requests: { authorization?: string; body: string }[] = [];
  const server = createServer(async (request, response) => {
    response.setHeader("Access-Control-Allow-Origin", "*");
    response.setHeader(
      "Access-Control-Allow-Headers",
      "authorization, content-type",
    );
    response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (request.method === "OPTIONS") {
      response.writeHead(204).end();
      return;
    }
    if (request.url === "/models") {
      response.setHeader("Content-Type", "application/json");
      response.end(
        '{"models":[{"slug":"z"},{"slug":"a"},{"slug":"hidden","visibility":"internal"}]}',
      );
      return;
    }
    if (request.url !== "/responses") {
      response.writeHead(404).end();
      return;
    }
    let body = "";
    for await (const bytes of request) body += bytes.toString();
    requests.push({ authorization: request.headers.authorization, body });
    response.setHeader("Content-Type", "text/event-stream");
    response.write(
      event({ type: "response.output_text.delta", delta: "Hello" }),
    );
    await remaining;
    response.write(
      event({
        type: "response.output_item.done",
        item: {
          type: "function_call",
          call_id: "call-weather",
          name: "weather",
          arguments: '{"city":"Copenhagen"}',
        },
      }),
    );
    response.end(event({ type: "response.completed" }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const running = page.evaluate(
      (base) => window.responsesTests.run(base),
      `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    );
    await page.waitForFunction(() => window.responsesText === "Hello");
    release();
    const result = await running;
    expect(result.models).toEqual(["z", "a"]);
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
    expect(requests[0].authorization).toBe("Bearer test-token");
    const body = JSON.parse(requests[0].body);
    expect(body.store).toBe(false);
    expect(body.tools[0].name).toBe("weather");
    expect(body.input[0].content[0].text).toBe("hello");
  } finally {
    release();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

for (const streamed of [false, true]) {
  test(`subscription failures remain typed (${streamed ? "SSE" : "HTTP"})`, async ({
    page,
  }) => {
    await page.route("**/responses-test/**", async (route) => {
      if (route.request().url().endsWith("/models")) {
        await route.fulfill({ json: { data: [{ id: "test" }] } });
      } else if (streamed) {
        await route.fulfill({
          contentType: "text/event-stream",
          body: event({
            type: "response.failed",
            response: {
              error: { code: "subscription_sharing_usage_limit_exceeded" },
            },
          }),
        });
      } else {
        await route.fulfill({
          status: 429,
          json: {
            error: { code: "subscription_sharing_usage_limit_exceeded" },
          },
        });
      }
    });
    const result = await page.evaluate(() =>
      window.responsesTests.run(`${location.origin}/responses-test`),
    );
    expect(result.failure).toBe("SubscriptionUsageLimitExceeded");
    expect(result.finished).toBe(false);
  });
}
