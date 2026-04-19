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
    const accessToken = typeof body.access_token === "string"
      ? body.access_token.trim()
      : "";
    const detectedPublicIp = extractClientIp(req);

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
            ssid,
          ),
        );
      case "bootstrap_signup_network":
        return json(
          await bootstrapSignupNetwork(
            adminClient,
            profile,
            user.id,
            detectedPublicIp,
            ssid,
            body,
          ),
        );
      case "list_store_networks":
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            ssid,
            await resolveTargetStore(adminClient, profile, body),
          ),
        );
      case "register_current_network": {
        const store = await resolveTargetStore(adminClient, profile, body, true);
        ensureCanManageNetworks(profile, String(store.id));
        await upsertStoreNetwork(
          adminClient,
          String(store.id),
          user.id,
          detectedPublicIp,
          ssid,
          typeof body.label === "string" ? body.label.trim() : null,
        );
        return json(
          await buildNetworkSnapshot(
            adminClient,
            profile,
            detectedPublicIp,
            ssid,
            store,
          ),
        );
      }
      case "deactivate_store_network": {
        const store = await resolveTargetStore(adminClient, profile, body);
        ensureCanManageNetworks(profile, String(store.id));
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
            ssid,
            store,
          ),
        );
      }
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

async function upsertStoreNetwork(
  adminClient: ReturnType<typeof createClient>,
  storeId: string,
  userId: string,
  publicIp: string,
  ssid: string | null,
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
    ssid_hint: ssid,
    label: label || ssid || null,
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

async function buildNetworkSnapshot(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  detectedPublicIp: string,
  ssid: string | null,
  store: Record<string, unknown>,
) {
  const { data } = await adminClient
    .from("store_networks")
    .select("id, public_ip, label, ssid_hint, is_active, last_seen_at")
    .eq("store_id", store.id)
    .order("is_active", { ascending: false })
    .order("created_at", { ascending: false });

  return {
    success: true,
    store_id: store.id,
    store_name: store.name,
    detected_public_ip: detectedPublicIp,
    ssid,
    can_manage_networks: canManageNetworks(profile, String(store.id)),
    networks: data ?? [],
  };
}

async function bootstrapSignupNetwork(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  userId: string,
  detectedPublicIp: string,
  ssid: string | null,
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
    ssid,
    "\uD68C\uC6D0\uAC00\uC785 \uC790\uB3D9 \uB4F1\uB85D",
  );

  return {
    success: true,
    message:
      "\uD604\uC7AC \uB124\uD2B8\uC6CC\uD06C\uB97C \uB9E4\uC7A5 \uD5C8\uC6A9 IP\uB85C \uB4F1\uB85D\uD588\uC2B5\uB2C8\uB2E4.",
    store_id: store.id,
    store_name: store.name,
    detected_public_ip: detectedPublicIp,
    ssid,
  };
}

async function checkLoginPolicy(
  adminClient: ReturnType<typeof createClient>,
  profile: Record<string, unknown>,
  userId: string,
  platform: string,
  detectedPublicIp: string,
  ssid: string | null,
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
      ssid,
      detected_public_ip: detectedPublicIp,
      can_manage_networks: canManageNetworks(
        profile,
        String(profile.store_id ?? ""),
      ),
    };
  }

  if (!role) {
    return {
      allowed: false,
      reason_code: "role_missing",
      message:
        "\uC5ED\uD560 \uC815\uBCF4\uAC00 \uC5C6\uC5B4 \uB85C\uADF8\uC778\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.",
      detected_public_ip: detectedPublicIp,
      ssid,
      can_manage_networks: false,
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
        ssid,
        can_manage_networks: canManageNetworks(profile, String(store.id)),
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
        ssid,
        can_manage_networks: false,
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
        ssid,
        can_manage_networks: false,
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
        ssid,
        can_manage_networks: false,
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
    ssid,
    can_manage_networks: canManageNetworks(
      profile,
      String(store?.id ?? profile.store_id ?? ""),
    ),
  };
}
