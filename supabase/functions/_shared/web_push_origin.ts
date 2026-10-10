/** Origini da cui NON consegnare Web Push (duplicano il banner Cronos della PWA). */
export function shouldSkipWebPushOrigin(origin: string): boolean {
  const o = String(origin || "").trim().toLowerCase();
  if (!o) return false;
  if (o.includes("pages.dev")) return true;
  try {
    const h = new URL(o).hostname;
    // Solo www: apex (gestopro360.it) è la scheda Chrome, non l'app installata.
    if (h === "gestopro360.it") return true;
    return false;
  } catch {
    return (
      o.includes("://gestopro360.it") &&
      !o.includes("://www.gestopro360.it")
    );
  }
}
