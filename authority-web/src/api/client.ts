import axios, { type AxiosError } from "axios";
import type { AuthUser } from "../types";

// The deployed Django API. This is a hard default rather than a dev convenience
// so a build with a missing/unset VITE_API_BASE_URL can never ship a console
// that points at a developer's machine.
export const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ||
  "https://civic-intelligence-api.onrender.com";

export const AUTH_UNAUTHORIZED_EVENT = "civic:unauthorized";

interface StoredSession {
  token: string;
  user: AuthUser;
}

const SESSION_KEY = "civic_authority_session";

export function getSession(): StoredSession | null {
  const raw = localStorage.getItem(SESSION_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as StoredSession;
  } catch {
    return null;
  }
}

export function saveSession(session: StoredSession): void {
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
}

export function clearSession(): void {
  localStorage.removeItem(SESSION_KEY);
}

export const client = axios.create({
  baseURL: API_BASE_URL,
  timeout: 20000,
});

// Attach the DRF token to every authority request.
client.interceptors.request.use((config) => {
  const token = getSession()?.token;
  if (token) {
    config.headers.Authorization = `Token ${token}`;
  }
  return config;
});

// A 401 means the token is missing, expired or the user lost staff access.
// Clear the local session and let the auth layer redirect to /login.
client.interceptors.response.use(
  (response) => response,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      clearSession();
      window.dispatchEvent(new CustomEvent(AUTH_UNAUTHORIZED_EVENT));
    }
    return Promise.reject(error);
  },
);

export function getErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    if (error.response?.status === 401) {
      return "Your session has expired. Please sign in again.";
    }
    if (!error.response) {
      return "Cannot reach the server. Check your connection and try again.";
    }
    const data = error.response.data as Record<string, unknown> | string;
    if (typeof data === "string") return data;
    if (typeof data.detail === "string") return data.detail;
    const keys = Object.keys(data);
    if (keys.length > 0) {
      const first = data[keys[0]];
      if (Array.isArray(first) && first.length > 0) return String(first[0]);
      if (typeof first === "string") return first;
    }
    return `Request failed (${error.response.status}).`;
  }
  return error instanceof Error ? error.message : "Something went wrong.";
}