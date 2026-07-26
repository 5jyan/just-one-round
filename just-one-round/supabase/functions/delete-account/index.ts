import { createClient } from "jsr:@supabase/supabase-js@2";

function response(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization || !supabaseUrl || !anonKey || !serviceRoleKey) {
    return response({ error: "Request is not authorized" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error: userError } = await userClient.auth.getUser();
  if (userError || !data.user) {
    return response({ error: "Request is not authorized" }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    data.user.id,
  );
  if (deleteError) {
    console.error("Account deletion failed", deleteError);
    return response({ error: "Account could not be deleted" }, 500);
  }

  return response({ deleted: true });
});
