import axios from "axios";
import { client, clearSession, getSession, saveSession } from "./client";
import type { AuthResponse, AuthUser } from "../types";

/**
 * Sign in against the existing Django endpoint and confirm authority access.
 *
 * The deployed `/api/auth/login/` serializer returns only
 * `{id, email, first_name, last_name, phone}` — it does NOT expose `is_staff`.
 * Gating on that field therefore rejects every real staff account, so authority
 * access is proven the only way the deployment can actually answer it: by
 * calling a staff-only endpoint with the freshly issued token.
 */
export async function login(email: string, password: string): Promise<AuthUser> {
  const { data } = await client.post<AuthResponse>("/api/auth/login/", {
    email,
    password,
  });

  const user: AuthUser = { ...data.user, is_staff: data.user.is_staff };
  await assertAuthorityAccess(data.token);

  saveSession({ token: data.token, user });
  return user;
}

/**
 * Probe a staff-only endpoint with `token` and classify the outcome.
 *
 *  - `staff`    the API answered 200: the token has authority access.
 *  - `denied`   the API answered 401/403: a valid citizen account, not staff.
 *  - `unavailable` the authority API itself is missing (404), so authority
 *               access cannot be established either way.
 */
export async function probeAuthorityAccess(
  token: string,
): Promise<"staff" | "denied" | "unavailable"> {
  try {
    // `page_size=1` keeps the probe cheap; the response body is irrelevant.
    const response = await axios.get("/api/authority/issues/", {
      baseURL: client.defaults.baseURL,
      timeout: 20000,
      params: { page_size: 1 },
      headers: { Authorization: `Token ${token}` },
    });
    return response.status < 400 ? "staff" : "denied";
  } catch (error) {
    if (axios.isAxiosError(error)) {
      const status = error.response?.status;
      if (status === 401 || status === 403) return "denied";
      // A 404 (or 405) means this deployment does not expose the authority API.
      if (status === 404 || status === 405) return "unavailable";
      if (!error.response) return "unavailable";
    }
    return "unavailable";
  }
}

async function assertAuthorityAccess(token: string): Promise<void> {
  const access = await probeAuthorityAccess(token);

  if (access === "denied") {
    throw new Error(
      "This account is not an authority account. The authority console is restricted to staff users.",
    );
  }

  if (access === "unavailable") {
    // Never leave a session behind when we could not verify access, so a
    // later 401 cannot be mistaken for an expired staff session.
    throw new Error(
      "Signed in, but the authority API could not be reached to verify staff access. Check that this deployment exposes /api/authority/ and that your account is a staff user.",
    );
  }
}

export function logout(): void {
  clearSession();
}

export { getSession };
