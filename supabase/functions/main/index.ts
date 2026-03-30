import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// Main edge function router — dispatches to individual functions
serve(async (req: Request) => {
  const url = new URL(req.url);
  const pathname = url.pathname;

  // Route /functions/v1/<name> to the matching function
  const match = pathname.match(/^\/([^/]+)/);
  if (!match) {
    return new Response("Not found", { status: 404 });
  }

  return new Response("Edge functions ready", { status: 200 });
});
