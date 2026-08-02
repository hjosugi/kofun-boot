import { createClient } from "./client";
const c = createClient({ baseUrl: "http://127.0.0.1:1" });
export const bad = c.get("/sum");
