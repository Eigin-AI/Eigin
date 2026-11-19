import { error } from "@sveltejs/kit";
/** Bound the entire multipart body before parsing, including requests without Content-Length. */
export async function boundedForm(request: Request, maxBytes = 300 * 1024) {
  const reader = request.body?.getReader();
  if (!reader) error(400, "Missing submission");
  const parts: Uint8Array<ArrayBuffer>[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      error(413, "Submission is too large.");
    }
    parts.push(new Uint8Array(value));
  }
  try {
    return await new Response(new Blob(parts), {
      headers: { "Content-Type": request.headers.get("content-type") || "" },
    }).formData();
  } catch {
    error(400, "Invalid submission form");
  }
}
