import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 允许的来源。默认是 GitHub Pages 站点，可用 Edge Function 环境变量 ALLOWED_ORIGIN 覆盖。
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "https://zzz12138-let.github.io";
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 3;

const corsHeaders = (origin: string) => ({
  "Access-Control-Allow-Origin": origin === ALLOWED_ORIGIN ? origin : ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const reply = (origin: string, body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
};

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") || "";

  if (request.method === "OPTIONS") {
    return origin === ALLOWED_ORIGIN
      ? new Response(null, { status: 204, headers: corsHeaders(origin) })
      : reply(origin, { error: "来源不允许" }, 403);
  }
  if (request.method !== "POST") return reply(origin, { error: "请求方法不允许" }, 405);
  if (origin !== ALLOWED_ORIGIN) return reply(origin, { error: "来源不允许" }, 403);

  let payload: { nickname?: unknown; message?: unknown; website?: unknown };
  try {
    payload = await request.json();
  } catch {
    return reply(origin, { error: "请求格式无效" }, 400);
  }

  // 蜜罐字段：正常访客看不到也不会填写，机器人常会填写 -> 假装成功并丢弃。
  if (payload.website) return reply(origin, { ok: true }, 201);

  const nickname = String(payload.nickname || "").trim();
  const message = String(payload.message || "").trim();
  if (nickname.length > 50 || message.length < 10 || message.length > 2000) {
    return reply(origin, { error: "请检查昵称和留言内容" }, 400);
  }

  const salt = Deno.env.get("RATE_LIMIT_SALT");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!salt || !supabaseUrl || !serviceKey) {
    console.error("submit-feedback: missing required environment variables");
    return reply(origin, { error: "服务暂不可用" }, 503);
  }

  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  const clientHash = await sha256(`${ip}:${salt}`);
  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
  const { count, error: countError } = await supabase
    .from("feedback")
    .select("id", { count: "exact", head: true })
    .eq("client_hash", clientHash)
    .gte("created_at", since);
  if (countError) {
    console.error("submit-feedback: rate limit query failed", countError.message);
    return reply(origin, { error: "服务暂不可用" }, 503);
  }
  if ((count || 0) >= RATE_LIMIT_MAX) {
    return reply(origin, { error: "提交过于频繁，请稍后再试" }, 429);
  }

  const { error } = await supabase.from("feedback").insert({ nickname, message, client_hash: clientHash });
  if (error) {
    console.error("submit-feedback: insert failed", error.message);
    return reply(origin, { error: "留言暂未保存，请稍后重试" }, 500);
  }
  return reply(origin, { ok: true }, 201);
});
