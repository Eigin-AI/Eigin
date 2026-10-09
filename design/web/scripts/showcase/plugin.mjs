// Dev-only endpoint behind the gallery's export buttons. It returns the image
// for the browser to save wherever you choose, or, given `out`, writes it into
// design/assets/showcase.
import { assetFile, displayPath, renderShot } from "./render.mjs";

/** @returns {import("vite").Plugin} */
export function showcaseExport() {
  return {
    name: "showcase-export",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/__showcase/export", async (req, res) => {
        if (req.method !== "POST") {
          res.statusCode = 405;
          return res.end();
        }
        try {
          let body = "";
          for await (const chunk of req) body += chunk;
          const { hash, out, format, width, height } = JSON.parse(body);
          if (typeof hash !== "string" || !hash.startsWith("#/showcase/")) {
            throw new Error("Expected a showcase hash");
          }
          const file = out ? assetFile(out) : undefined;
          const image = await renderShot({
            origin: `http://${req.headers.host}`,
            hash,
            width: Number(width),
            height: Number(height),
            out: file,
            format: format === "jpg" ? "jpg" : "png",
          });
          if (file) return res.end(displayPath(file));
          res.setHeader("Content-Type", format === "jpg" ? "image/jpeg" : "image/png");
          res.end(image);
        } catch (error) {
          res.statusCode = 500;
          res.end(error instanceof Error ? error.message : String(error));
        }
      });
    },
  };
}
