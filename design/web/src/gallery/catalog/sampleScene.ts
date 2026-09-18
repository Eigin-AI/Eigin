/**
 * A stand-in for photography: a drawn scene at a given shape, as a data URI.
 *
 * Specimens need real pixels at real aspect ratios to show cropping and the
 * width settle, and a drawing keeps the gallery off the network.
 */
export function scene(width: number, height: number): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFCA8B"/><stop offset="1" stop-color="#DEC8B0"/>
    </linearGradient></defs>
    <rect width="${width}" height="${height}" fill="url(#sky)"/>
    <circle cx="${width * 0.72}" cy="${height * 0.28}" r="${Math.min(width, height) * 0.13}" fill="#FCAF53"/>
    <path d="M0 ${height} L0 ${height * 0.72} Q${width * 0.3} ${height * 0.44} ${width * 0.56} ${height * 0.7} T${width} ${height * 0.6} L${width} ${height} Z" fill="#A7B04E"/>
    <path d="M0 ${height} L0 ${height * 0.86} Q${width * 0.34} ${height * 0.64} ${width * 0.62} ${height * 0.87} T${width} ${height * 0.8} L${width} ${height} Z" fill="#4A7A52"/>
  </svg>`;
  /* Brackets too: these URIs sit inside markdown image syntax. */
  const encoded = encodeURIComponent(svg.replace(/\s+/g, " "))
    .replace(/\(/g, "%28")
    .replace(/\)/g, "%29");
  return `data:image/svg+xml,${encoded}`;
}
