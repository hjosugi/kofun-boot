import { createClient } from "./client";
const c = createClient({ baseUrl: "http://127.0.0.1:1" });
export const a = c.get("/hello");
export const b = c.post("/sum", { left: 1, right: 2 });
export const d = c.get("/bench");
export const e = c.post("/bench");
