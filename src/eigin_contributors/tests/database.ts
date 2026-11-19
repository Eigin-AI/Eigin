/** Accept only the loopback database and generated credentials from the test runner. */
export function testDatabaseUrl() {
  const url = process.env.TEST_DATABASE_URL;
  const disposable =
    /^postgresql:\/\/contributors_test:([a-f0-9]{32})@127\.0\.0\.1:[1-9]\d*\/contributors_test_\1$/;
  if (!url || !disposable.test(url))
    throw new Error("Run database tests with just test contributor postgres");
  return url;
}
