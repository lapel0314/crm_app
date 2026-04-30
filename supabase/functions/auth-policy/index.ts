import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MOBILE_PLATFORMS = new Set(["android", "ios"]);
const PRIVILEGED_ROLES = new Set([
  "\uB300\uD45C",
  "\uAC1C\uBC1C\uC790",
]);
const MANAGER_ROLES = new Set(["\uC810\uC7A5"]);
const MANAGE_NETWORK_ROLES = new Set([
  "\uB300\uD45C",
  "\uAC1C\uBC1C\uC790",
  "\uC810\uC7A5",
]);
const STAFF_ROLE = "\uC0AC\uC6D0";

type ClientNetwork = {
  ssid: string | null;
  wifiIp: string | null;
  wifiGatewayIp: string | null;
  wifiBssid: string | null;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const userClient = createClient(supabaseUrl, anonKey);
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "check_login_policy");
    const platform = String(body.platform ?? "unknown").toLowerCase();
    const ssid = typeof body.ssid === "string" ? body.ssid.trim() : null;
    const wifiIp = cleanOptionalString(body.wifi_ip);
    const wifiGatewayIp = cleanOptionalString(body.wifi_gateway_ip);
    const wifiBssid = cleanOptionalString(body.wifi_bssid);
    const accessToken = typeof body.access_token === "string"
      ? body.access_token.trim()
      : "";
    const detectedPublicIp = extractClientIp(req);
    const clientNetwork = { ssid, wifiIp, wifiGatewayIp, wifiBssid };

    if (!accessToken) {
      return json(
        { success: false, message: "\uC778\uC99D \uD1A0\uD070\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." },
        401,
      );
    }

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser(accessToken);

    if (userError || !user) {
      return json(
        { success: false, message: "\uC778\uC99D \uC138\uC158\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." },
        401,
      );
    }

    const profile = await loadProfile(adminClient, user.id);
    if (!profile) {
      return json(
        {
          allowed: false,
          success: false,
          reason_code: "profile_not_found",
          message:
            "\uD504\uB85C\uD544 \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4. \uAD00\uB9AC\uC790\uC5D0\uAC8C \uBB38\uC758\uD574\uC8FC\uC138\uC694.",
        },
        403,
      );
    }

    switch (action) {
      case "check_login_policy":
        return json(
          await checkLoginPolicy(
            adminClient,
            profile,
            user.id,
            platform,
            detectedPublicIp,
            clientNetwork,
          ),
        );
      case "bootstrap_signup_network":
        return json(
          await bootstrapSignupNetwork(
            adminClient,
            profile,
            user.id,
            detectedPublicIp,
            clientNetwork,
            body,
          ),
        );
      case "list_store_networks":
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            await resolveTargetStore(adminClient, profile, body),
          ),
        );
      case "register_current_network": {
        const store = await resolveTargetStore(adminClient, profile, body, true);
        ensureCanModifyStoreNetworks(profile);
        await upsertStoreNetwork(
          adminClient,
          String(store.id),
          user.id,
          detectedPublicIp,
          clientNetwork,
          typeof body.label === "string" ? body.label.trim() : null,
        );
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "request_current_network": {
        const store = await resolveTargetStore(adminClient, profile, body);
        ensureCanRequestStoreNetwork(profile, String(store.id));
        await upsertNetworkRequest(
          adminClient,
          String(store.id),
          user.id,
          detectedPublicIp,
          clientNetwork,
          typeof body.label === "string" ? body.label.trim() : null,
        );
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "approve_network_request": {
        ensureCanModifyStoreNetworks(profile);
        const requestId = String(body.request_id ?? "");
        const request = await loadPendingNetworkRequest(adminClient, requestId);
        await upsertStoreNetwork(
          adminClient,
          String(request.store_id),
          user.id,
          String(request.public_ip),
          {
            ssid: cleanOptionalString(request.ssid_hint),
            wifiIp: cleanOptionalString(request.wifi_ip),
            wifiGatewayIp: cleanOptionalString(request.wifi_gateway_ip),
            wifiBssid: cleanOptionalString(request.wifi_bssid),
          },
          cleanOptionalString(request.label) ?? "\uC2B9\uC778\uB41C \uB124\uD2B8\uC6CC\uD06C \uC694\uCCAD",
        );
        await adminClient
          .from("store_network_requests")
          .update({
            status: "approved",
            reviewed_by: user.id,
            reviewed_at: new Date().toISOString(),
          })
          .eq("id", request.id);
        const store = await loadStore(adminClient, String(request.store_id));
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "reject_network_request": {
        ensureCanModifyStoreNetworks(profile);
        const requestId = String(body.request_id ?? "");
        const request = await loadPendingNetworkRequest(adminClient, requestId);
        await adminClient
          .from("store_network_requests")
          .update({
            status: "rejected",
            reviewed_by: user.id,
            reviewed_at: new Date().toISOString(),
          })
          .eq("id", request.id);
        const store = await loadStore(adminClient, String(request.store_id));
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "deactivate_store_network": {
        const store = await resolveTargetStore(adminClient, profile, body);
        ensureCanModifyStoreNetworks(profile);
        const networkId = String(body.network_id ?? "");
        if (!networkId) {
          return json(
            {
              success: false,
              message:
                "\uBE44\uD65C\uC131\uD654\uD560 \uB124\uD2B8\uC6CC\uD06C\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.",
            },
            400,
          );
        }
        await adminClient
          .from("store_networks")
          .update({ is_active: false })
          .eq("id", networkId)
          .eq("store_id", store.id);
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "update_store_network_label": {
        const store = await resolveTargetStore(adminClient, profile, body);
        ensureCanModifyStoreNetworks(profile);
        const networkId = String(body.network_id ?? "");
        const label = cleanOptionalString(body.label);
        if (!networkId) {
          return json(
            {
              success: false,
              message: "\uBCC0\uACBD\uD560 \uB124\uD2B8\uC6CC\uD06C\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.",
            },
            400,
          );
        }
        await adminClient
          .from("store_networks")
          .update({ label })
          .eq("id", networkId)
          .eq("store_id", store.id);
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            clientNetwork,
            store,
          ),
        );
      }
      case "delete_notice":
        return json(await deleteNotice(adminClient, profile, body));
      case "admin_update_user_password":
        return json(await adminUpdateUserPassword(adminClient, profile, body));
      default:
        return json(
          {
            success: false,
            message: "\uC9C0\uC6D0\uD558\uC9C0 \uC54A\uB294 \uC694\uCCAD\uC785\uB2C8\uB2E4.",
          },
          400,
        );
    }
  } catch (error) {
    console.error(error);
    return json(
      {
        success: false,
        message:
          error instanceof Error
            ? error.message
            : "\uC11C\uBC84 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4.",
      },
      500,
    );
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function extractClientIp(req: Request) {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    return forwarded.split(",")[0].trim();
  }
  return (
    req.headers.get("x-real-ip") ??
    req.headers.get("cf-connecting-ip") ??
    "unknown"
  );
}

function cleanOptionalString(value: unknown) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned ? cleaned : null;
}

function networkPayload(clientNetwork: ClientNetwork) {
  return {
    ssid: clientNetwork.ssid,
    wifi_ip: clientNetwork.wifiIp,
    wifi_gateway_ip: clientNetwork.wifiGatewayIp,
    wifi_bssid: clientNetwork.wifiBssid,
  };
}

function normalizeStoreName(input: string) {
  let value = (input ?? "").trim();
  if (!value) return "";
  value = value
    .replace(/\s+/g, "")
    .replaceAll("\uB9E4\uC7A5", "")
    .replaceAll("\uC9C0\uC810", "")
    .replaceAll("\uC2A4\uD1A0\uC5B4", "")
    .replace(/\uC810$/, "");
  if (!value) return "";
  return `${value}\uC810`;
}

function roleText(profile: Record<string, unknown>) {
  return String(profile.role_code ?? profile.role ?? "");
}

function isPrivileged(profile: Record<string, unknown>) {
  return PRIVILEGED_ROLES.has(roleText(profile));
}

function isManager(profile: Record<string, unknown>) {
  return MANAGER_ROLES.has(roleText(profile));
}

function canManageNetworks(
  profile: Record<string, unknown>,
  targetStoreId?: string,
) {
  if (isPrivileged(profile)) return true;
  return isManager(profile) &&
    (!targetStoreId || String(profile.store_id ?? "") === targetStoreId);
}

async function loadProfile(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
) {
  const { data } = await adminClient
    .from("profiles")
    .select("id, role, role_code, approval_status, store, store_id")
    .eq("id", userId)
    .maybeSingle();
  return data as Record<string, unknown> | null;
}

async function loadStore(
  adminClient: ReturnType<typeof createClient>,
  storeId: string,
) {
  const { data } = await adminClient
    .from("stores")
    .select("id, name, normalized_name, is_active")
    .eq("id", storeId)
    .maybeSingle();
  if (!data) {
    throw new Error(
      "\uB9E4\uC7A5 \uC815\uBCF4\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
    );
  }
  return data as Record<string, unknown>;
}

async function ensureStore(
  adminClient: ReturnType<typeof createClient>,
  storeName: string,
  userId: string,
) {
  const normalizedName = normalizeStoreName(storeName);
  if (!normalizedName) {
    throw new Error("\uB9E4\uC7A5\uBA85\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.");
  }

  const { data, error } = await adminClient
    .from("stores")
    .upsert(
      {
        name: normalizedName,
        normalized_name: normalizedName,
        is_active: true,
        created_by: userId,
      },
      { onConflict: "normalized_name" },
    )
    .select("id, name, normalized_name, is_active")
    .single();

  if (error || !data) {
    throw new Error(
      "\uB9E4\uC7A5 \uC815\uBCF4\uB97C \uC0DD\uC131\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.",
    );
  }

  return data as Record<string, unknown>;
}

async function resolveTargetStore(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  body: Record<string, unknown>,
  allowCreate = false,
) {
  const requestedStoreId = String(body.store_id ?? "");
  const requestedStoreName = String(body.store_name ?? "");

  if (requestedStoreId) {
    return await loadStore(adminClient, requestedStoreId);
  }

  const profileStoreId = String(profile.store_id ?? "");
  if (profileStoreId) {
    return await loadStore(adminClient, profileStoreId);
  }

  if (allowCreate && requestedStoreName) {
    return await ensureStore(adminClient, requestedStoreName, String(profile.id));
  }

  throw new Error(
    "\uB300\uC0C1 \uB9E4\uC7A5\uC744 \uD655\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
  );
}

function ensureCanManageNetworks(
  profile: Record<string, unknown>,
  storeId: string,
) {
  if (!canManageNetworks(profile, storeId)) {
    throw new Error(
      "\uD604\uC7AC \uACC4\uC815\uC740 \uB9E4\uC7A5 \uB124\uD2B8\uC6CC\uD06C\uB97C \uAD00\uB9AC\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
    );
  }
}

function ensureCanModifyStoreNetworks(profile: Record<string, unknown>) {
  if (!isPrivileged(profile)) {
    throw new Error(
      "\uB9E4\uC7A5 \uB124\uD2B8\uC6CC\uD06C \uB4F1\uB85D/\uBCC0\uACBD\uC740 \uB300\uD45C \uB610\uB294 \uAC1C\uBC1C\uC790\uB9CC \uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.",
    );
  }
}

function ensureCanRequestStoreNetwork(
  profile: Record<string, unknown>,
  storeId: string,
) {
  if (!canManageNetworks(profile, storeId)) {
    throw new Error(
      "\uD604\uC7AC \uACC4\uC815\uC740 \uB9E4\uC7A5 \uB124\uD2B8\uC6CC\uD06C \uB4F1\uB85D\uC744 \uC694\uCCAD\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
    );
  }
}

async function loadPendingNetworkRequest(
  adminClient: ReturnType<typeof createClient>,
  requestId: string,
) {
  if (!requestId) {
    throw new Error("\uCC98\uB9AC\uD560 \uB124\uD2B8\uC6CC\uD06C \uC694\uCCAD\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.");
  }

  const { data, error } = await adminClient
    .from("store_network_requests")
    .select(
      "id, store_id, public_ip, label, ssid_hint, wifi_ip, wifi_gateway_ip, wifi_bssid, status",
    )
    .eq("id", requestId)
    .eq("status", "pending")
    .maybeSingle();

  if (error || !data) {
    throw new Error("\uB300\uAE30 \uC911\uC778 \uB124\uD2B8\uC6CC\uD06C \uC694\uCCAD\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
  }

  return data as Record<string, unknown>;
}

async function upsertStoreNetwork(
  adminClient: ReturnType<typeof createClient>,
  storeId: string,
  userId: string,
  publicIp: string,
  clientNetwork: ClientNetwork,
  label: string | null,
) {
  if (!publicIp || publicIp === "unknown") {
    throw new Error(
      "\uD604\uC7AC \uACF5\uC778 IP\uB97C \uD655\uC778\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.",
    );
  }

  const payload = {
    store_id: storeId,
    public_ip: publicIp,
    ssid_hint: clientNetwork.ssid,
    label: label || clientNetwork.ssid || clientNetwork.wifiGatewayIp || null,
    is_active: true,
    registered_by: userId,
    last_seen_at: new Date().toISOString(),
  };

  const { error } = await adminClient
    .from("store_networks")
    .upsert(payload, { onConflict: "store_id,public_ip" });

  if (error) {
    throw new Error(
      "\uB9E4\uC7A5 \uB124\uD2B8\uC6CC\uD06C\uB97C \uB4F1\uB85D\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.",
    );
  }
}

async function upsertNetworkRequest(
  adminClient: ReturnType<typeof createClient>,
  storeId: string,
  userId: string,
  publicIp: string,
  clientNetwork: ClientNetwork,
  label: string | null,
) {
  if (!publicIp || publicIp === "unknown") {
    throw new Error(
      "\uD604\uC7AC \uACF5\uC778 IP\uB97C \uD655\uC778\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.",
    );
  }

  const { data: existingNetwork } = await adminClient
    .from("store_networks")
    .select("id")
    .eq("store_id", storeId)
    .eq("public_ip", publicIp)
    .eq("is_active", true)
    .maybeSingle();

  if (existingNetwork) {
    throw new Error("\uC774\uBBF8 \uD5C8\uC6A9\uB41C \uB9E4\uC7A5 \uB124\uD2B8\uC6CC\uD06C\uC785\uB2C8\uB2E4.");
  }

  const payload = {
    store_id: storeId,
    public_ip: publicIp,
    label: label || clientNetwork.ssid || clientNetwork.wifiGatewayIp || null,
    ssid_hint: clientNetwork.ssid,
    wifi_ip: clientNetwork.wifiIp,
    wifi_gateway_ip: clientNetwork.wifiGatewayIp,
    wifi_bssid: clientNetwork.wifiBssid,
    requested_by: userId,
    status: "pending",
    requested_at: new Date().toISOString(),
    reviewed_by: null,
    reviewed_at: null,
  };

  const { data: existingRequest } = await adminClient
    .from("store_network_requests")
    .select("id")
    .eq("store_id", storeId)
    .eq("public_ip", publicIp)
    .eq("status", "pending")
    .maybeSingle();

  const { error } = existingRequest
    ? await adminClient
      .from("store_network_requests")
      .update(payload)
      .eq("id", existingRequest.id)
    : await adminClient
      .from("store_network_requests")
      .insert(payload);

  if (error) {
    throw new Error("\uB124\uD2B8\uC6CC\uD06C \uB4F1\uB85D \uC694\uCCAD\uC744 \uC800\uC7A5\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.");
  }
}

async function buildNetworkSnapshot(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  detectedPublicIp: string,
  clientNetwork: ClientNetwork,
  store: Record<string, unknown>,
) {
  const { data } = await adminClient
    .from("store_networks")
    .select("id, public_ip, label, ssid_hint, is_active, last_seen_at")
    .eq("store_id", store.id)
    .order("is_active", { ascending: false })
    .order("created_at", { ascending: false });

  const { data: pendingRequests } = canManageNetworks(profile, String(store.id))
    ? await adminClient
      .from("store_network_requests")
      .select(
        "id, public_ip, label, ssid_hint, wifi_ip, wifi_gateway_ip, requested_at, requested_by_profile:profiles!store_network_requests_requested_by_fkey(name)",
      )
      .eq("store_id", store.id)
      .eq("status", "pending")
      .order("requested_at", { ascending: false })
    : { data: [] };

  const { data: requestHistory } = canManageNetworks(profile, String(store.id))
    ? await adminClient
      .from("store_network_requests")
      .select(
        "id, public_ip, label, ssid_hint, status, requested_at, reviewed_at, requested_by_profile:profiles!store_network_requests_requested_by_fkey(name), reviewed_by_profile:profiles!store_network_requests_reviewed_by_fkey(name)",
      )
      .eq("store_id", store.id)
      .neq("status", "pending")
      .order("reviewed_at", { ascending: false })
      .limit(20)
    : { data: [] };

  const { data: staffProfiles } = canManageNetworks(profile, String(store.id))
    ? await adminClient
      .from("profiles")
      .select("name, role, role_code, last_login_at, last_login_public_ip")
      .eq("store_id", store.id)
      .eq("approval_status", "approved")
      .order("last_login_at", { ascending: false, nullsFirst: false })
    : { data: [] };

  const staffRows = (staffProfiles ?? []).filter((staff) =>
    String(staff.role_code ?? staff.role ?? "") === STAFF_ROLE
  );
  const recentStaff = staffRows.find((staff) => staff.last_login_at);

  return {
    success: true,
    store_id: store.id,
    store_name: store.name,
    detected_public_ip: detectedPublicIp,
    ssid: clientNetwork.ssid,
    wifi_ip: clientNetwork.wifiIp,
    wifi_gateway_ip: clientNetwork.wifiGatewayIp,
    wifi_bssid: clientNetwork.wifiBssid,
    can_manage_networks: canManageNetworks(profile, String(store.id)),
    can_modify_networks: isPrivileged(profile),
    security_summary: {
      active_network_count: (data ?? []).filter((network) => network.is_active !== false).length,
      inactive_network_count: (data ?? []).filter((network) => network.is_active === false).length,
      pending_request_count: (pendingRequests ?? []).length,
      staff_count: staffRows.length,
      recent_staff_login_at: recentStaff?.last_login_at ?? null,
      recent_staff_login_public_ip: recentStaff?.last_login_public_ip ?? null,
      recent_staff_login_name: recentStaff?.name ?? null,
    },
    networks: data ?? [],
    pending_network_requests: (pendingRequests ?? []).map((request) => ({
      id: request.id,
      public_ip: request.public_ip,
      label: request.label,
      ssid_hint: request.ssid_hint,
      wifi_ip: request.wifi_ip,
      wifi_gateway_ip: request.wifi_gateway_ip,
      requested_at: request.requested_at,
      requested_by_name: Array.isArray(request.requested_by_profile)
        ? request.requested_by_profile[0]?.name
        : request.requested_by_profile?.name,
    })),
    network_request_history: (requestHistory ?? []).map((request) => ({
      id: request.id,
      public_ip: request.public_ip,
      label: request.label,
      ssid_hint: request.ssid_hint,
      status: request.status,
      requested_at: request.requested_at,
      reviewed_at: request.reviewed_at,
      requested_by_name: Array.isArray(request.requested_by_profile)
        ? request.requested_by_profile[0]?.name
        : request.requested_by_profile?.name,
      reviewed_by_name: Array.isArray(request.reviewed_by_profile)
        ? request.reviewed_by_profile[0]?.name
        : request.reviewed_by_profile?.name,
    })),
  };
}

async function bootstrapSignupNetwork(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  userId: string,
  detectedPublicIp: string,
  clientNetwork: ClientNetwork,
  body: Record<string, unknown>,
) {
  if (!MANAGE_NETWORK_ROLES.has(roleText(profile))) {
    return {
      success: true,
      message:
        "\uD604\uC7AC \uC5ED\uD560\uC740 \uB124\uD2B8\uC6CC\uD06C \uC790\uB3D9 \uB4F1\uB85D \uB300\uC0C1\uC774 \uC544\uB2D9\uB2C8\uB2E4.",
    };
  }

  const requestedStoreName = String(body.store_name ?? profile.store ?? "");
  const store = await ensureStore(adminClient, requestedStoreName, userId);

  await adminClient
    .from("profiles")
    .update({
      store_id: store.id,
      store: store.name,
    })
    .eq("id", userId);

  await upsertStoreNetwork(
    adminClient,
    String(store.id),
    userId,
    detectedPublicIp,
    clientNetwork,
    "\uD68C\uC6D0\uAC00\uC785 \uC790\uB3D9 \uB4F1\uB85D",
  );

  return {
    success: true,
    message:
      "\uD604\uC7AC \uB124\uD2B8\uC6CC\uD06C\uB97C \uB9E4\uC7A5 \uD5C8\uC6A9 IP\uB85C \uB4F1\uB85D\uD588\uC2B5\uB2C8\uB2E4.",
    store_id: store.id,
    store_name: store.name,
    detected_public_ip: detectedPublicIp,
    ssid: clientNetwork.ssid,
    wifi_ip: clientNetwork.wifiIp,
    wifi_gateway_ip: clientNetwork.wifiGatewayIp,
    wifi_bssid: clientNetwork.wifiBssid,
    can_modify_networks: isPrivileged(profile),
  };
}

async function adminUpdateUserPassword(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  body: Record<string, unknown>,
) {
  if (!isPrivileged(profile)) {
    return {
      success: false,
      message: "현재 계정은 직원 비밀번호를 변경할 수 없습니다.",
    };
  }

  const targetUserId = String(body.user_id ?? "").trim();
  const password = String(body.password ?? "");

  if (!targetUserId) {
    return {
      success: false,
      message: "비밀번호를 변경할 직원을 선택해 주세요.",
    };
  }

  if (password.length < 8) {
    return {
      success: false,
      message: "비밀번호는 8자 이상이어야 합니다.",
    };
  }

  const { data: targetProfile, error: profileError } = await adminClient
    .from("profiles")
    .select("id, email, name")
    .eq("id", targetUserId)
    .maybeSingle();

  if (profileError) {
    throw new Error("직원 정보를 확인하지 못했습니다.");
  }

  if (!targetProfile) {
    return {
      success: false,
      message: "직원 정보를 찾을 수 없습니다.",
    };
  }

  const { error: updateError } = await adminClient.auth.admin.updateUserById(
    targetUserId,
    { password },
  );

  if (updateError) {
    throw new Error(`비밀번호 변경 실패: ${updateError.message}`);
  }

  await adminClient.from("audit_logs").insert({
    actor_id: String(profile.id ?? ""),
    action: "admin_update_user_password",
    target_table: "auth.users",
    target_id: targetUserId,
    detail: {
      target_email: targetProfile.email ?? null,
      target_name: targetProfile.name ?? null,
    },
  }).then(({ error }) => {
    if (error) console.error("password audit insert failed", error);
  });

  return {
    success: true,
    message: "비밀번호가 변경되었습니다.",
  };
}

async function deleteNotice(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  body: Record<string, unknown>,
) {
  if (!isPrivileged(profile)) {
    return {
      success: false,
      message: "현재 계정은 공지사항을 삭제할 수 없습니다.",
    };
  }

  const noticeId = String(body.notice_id ?? "").trim();
  if (!noticeId) {
    return {
      success: false,
      message: "삭제할 공지사항 ID가 없습니다.",
    };
  }

  const { data: notice, error: noticeError } = await adminClient
    .from("crm_notices")
    .select("id, image_path")
    .eq("id", noticeId)
    .maybeSingle();

  if (noticeError) {
    throw new Error("공지사항 정보를 확인하지 못했습니다.");
  }

  if (!notice) {
    return {
      success: false,
      message: "공지사항을 찾을 수 없습니다.",
    };
  }

  const { error: updateError } = await adminClient
    .from("crm_notices")
    .update({ is_active: false })
    .eq("id", noticeId);

  if (updateError) {
    throw new Error("공지사항을 삭제하지 못했습니다.");
  }

  const imagePath = String(notice.image_path ?? "").trim();
  if (imagePath) {
    const { error: storageError } = await adminClient.storage
      .from("crm-notice-images")
      .remove([imagePath]);
    if (storageError) {
      console.error("delete_notice storage remove failed", storageError);
    }
  }

  return {
    success: true,
    message: "공지사항이 삭제되었습니다.",
  };
}

async function checkLoginPolicy(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  userId: string,
  platform: string,
  detectedPublicIp: string,
  clientNetwork: ClientNetwork,
) {
  const role = roleText(profile);
  const approvalStatus = String(profile.approval_status ?? "pending");

  if (approvalStatus !== "approved") {
    return {
      allowed: false,
      reason_code: "approval_pending",
      message:
        "\uC2B9\uC778\uB41C \uACC4\uC815\uB9CC \uB85C\uADF8\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.",
      role,
      ...networkPayload(clientNetwork),
      detected_public_ip: detectedPublicIp,
      can_manage_networks: canManageNetworks(
        profile,
        String(profile.store_id ?? ""),
      ),
      can_modify_networks: isPrivileged(profile),
    };
  }

  if (!role) {
    return {
      allowed: false,
      reason_code: "role_missing",
      message:
        "\uC5ED\uD560 \uC815\uBCF4\uAC00 \uC5C6\uC5B4 \uB85C\uADF8\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
      detected_public_ip: detectedPublicIp,
      ...networkPayload(clientNetwork),
      can_manage_networks: false,
      can_modify_networks: false,
    };
  }

  let store: Record<string, unknown> | null = null;
  const storeId = String(profile.store_id ?? "");
  if (storeId) {
    store = await loadStore(adminClient, storeId);
    if (store.is_active === false) {
      return {
        allowed: false,
        reason_code: "store_inactive",
        message:
          "\uBE44\uD65C\uC131\uD654\uB41C \uB9E4\uC7A5 \uACC4\uC815\uC785\uB2C8\uB2E4.",
        role,
        store_id: store.id,
        store_name: store.name,
        detected_public_ip: detectedPublicIp,
        ...networkPayload(clientNetwork),
        can_manage_networks: canManageNetworks(profile, String(store.id)),
        can_modify_networks: isPrivileged(profile),
      };
    }
  }

  if (role === STAFF_ROLE) {
    if (!MOBILE_PLATFORMS.has(platform)) {
      return {
        allowed: false,
        reason_code: "staff_mobile_only",
        message:
          "\uC0AC\uC6D0 \uACC4\uC815\uC740 \uBAA8\uBC14\uC77C\uC5D0\uC11C\uB9CC \uB85C\uADF8\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.",
        role,
        store_id: store?.id,
        store_name: store?.name,
        detected_public_ip: detectedPublicIp,
        ...networkPayload(clientNetwork),
        can_manage_networks: false,
        can_modify_networks: false,
      };
    }

    if (!store) {
      return {
        allowed: false,
        reason_code: "staff_store_missing",
        message:
          "\uC0AC\uC6D0 \uACC4\uC815\uC740 \uB9E4\uC7A5 \uC815\uBCF4\uAC00 \uC5F0\uACB0\uB418\uC5B4 \uC788\uC5B4\uC57C \uD569\uB2C8\uB2E4.",
        role,
        detected_public_ip: detectedPublicIp,
        ...networkPayload(clientNetwork),
        can_manage_networks: false,
        can_modify_networks: false,
      };
    }

    const { data: matchedNetwork } = await adminClient
      .from("store_networks")
      .select("id")
      .eq("store_id", store.id)
      .eq("is_active", true)
      .eq("public_ip", detectedPublicIp)
      .maybeSingle();

    if (!matchedNetwork) {
      return {
        allowed: false,
        reason_code: "staff_network_blocked",
        message:
          "\uC0AC\uC6D0 \uACC4\uC815\uC740 \uB4F1\uB85D\uB41C \uB9E4\uC7A5 \uACF5\uC778 IP\uC5D0\uC11C\uB9CC \uB85C\uADF8\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.",
        role,
        store_id: store.id,
        store_name: store.name,
        detected_public_ip: detectedPublicIp,
        ...networkPayload(clientNetwork),
        can_manage_networks: false,
        can_modify_networks: false,
      };
    }

    await adminClient
      .from("store_networks")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("id", matchedNetwork.id);
  }

  await adminClient
    .from("profiles")
    .update({
      last_login_platform: platform,
      last_login_public_ip: detectedPublicIp,
      last_login_at: new Date().toISOString(),
      login_policy_message: null,
    })
    .eq("id", userId);

  return {
    allowed: true,
    success: true,
    message:
      "\uB85C\uADF8\uC778\uC774 \uD5C8\uC6A9\uB418\uC5C8\uC2B5\uB2C8\uB2E4.",
    role,
    store_id: store?.id ?? profile.store_id ?? null,
    store_name: store?.name ?? profile.store ?? null,
    detected_public_ip: detectedPublicIp,
    ...networkPayload(clientNetwork),
    can_manage_networks: canManageNetworks(
      profile,
      String(store?.id ?? profile.store_id ?? ""),
    ),
    can_modify_networks: isPrivileged(profile),
  };
}
