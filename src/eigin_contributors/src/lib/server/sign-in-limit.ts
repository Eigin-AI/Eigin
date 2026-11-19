const minute = 60_000;
const perAddress = 10;
const perProcess = 120;

/** Bound each address and total OAuth starts before touching PostgreSQL. */
export function signInLimit(now = Date.now) {
  let resetsAt = 0;
  let total = 0;
  const addresses = new Map<string, number>();
  return (address: string) => {
    const time = now();
    if (time >= resetsAt) {
      resetsAt = time + minute;
      total = 0;
      addresses.clear();
    }
    const started = addresses.get(address) ?? 0;
    if (started >= perAddress || total >= perProcess)
      return Math.max(1, Math.ceil((resetsAt - time) / 1000));
    addresses.set(address, started + 1);
    total++;
    return 0;
  };
}
