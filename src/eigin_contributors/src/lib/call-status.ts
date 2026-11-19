/** A call opens at its opening instant and closes at its deadline. */
export function callStatus(
  opensAt: string,
  closesAt: string,
  now: number,
): "upcoming" | "open" | "closed" {
  if (now >= Date.parse(closesAt)) return "closed";
  return now < Date.parse(opensAt) ? "upcoming" : "open";
}
