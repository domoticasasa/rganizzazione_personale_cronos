// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

const allowedSlots = new Set(["08:00", "11:50", "14:00", "16:30", "manual_test"]);

function inferSlotFromNow(now: Date): string {
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  try {
    let body: Record<string, unknown> = {};
    if (req.method !== "GET") {
      try {
        body = (await req.json()) ?? {};
      } catch (_) {
        body = {};
      }
    }
    const inputSlot = String(body.slot ?? req.headers.get("x-reminder-slot") ?? "")
      .trim();
    const slot = inputSlot || inferSlotFromNow(new Date());
    if (!allowedSlots.has(slot)) {
      return json({
        ok: false,
        error: "slot non valido",
        allowed_slots: Array.from(allowedSlots),
      }, 400);
    }

    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await supa.rpc(
      "notify_mezzi_km_missing_for_slot",
      { slot_key: slot },
    );
    if (error) {
      return json({ ok: false, error: error.message }, 500);
    }
    return json({
      ok: true,
      slot,
      notifiche_generate: Number(data ?? 0),
    });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
