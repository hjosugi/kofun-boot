# Client type fixtures

`accepts.ts` must compile. The other two must **not**, and the gate asserts the
error rather than only the failure — a client that rejected every call would
also make them fail, and would be useless.

They import `./client`, which the gate copies from the generated
`contracts/client.ts`, so the fixtures type-check against the client a caller
would actually install.
