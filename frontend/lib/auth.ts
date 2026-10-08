import { useEffect, useState } from "react";

const ID_TOKEN_KEY = "peach_id_token";
const ACCESS_TOKEN_KEY = "peach_access_token";
const REFRESH_TOKEN_KEY = "peach_refresh_token";

const COGNITO_REGION = process.env.NEXT_PUBLIC_COGNITO_REGION || "us-east-1";
const COGNITO_CLIENT_ID = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID || "5f96rjbr4ctcqv1248m5tunj8o";
const COGNITO_DOMAIN = process.env.NEXT_PUBLIC_COGNITO_DOMAIN || "peach-auth-757159686525.auth.us-east-1.amazoncognito.com";
export const COGNITO_GOOGLE_ENABLED = process.env.NEXT_PUBLIC_COGNITO_GOOGLE_ENABLED === "true";

export function getRedirectUri(): string {
  if (typeof window === "undefined") return "http://localhost:3000/auth/callback";
  return `${window.location.origin}/auth/callback`;
}

export function signInWithGoogle(): void {
  if (!COGNITO_DOMAIN) {
    throw new Error("COGNITO_DOMAIN is not configured");
  }
  const redirectUri = encodeURIComponent(getRedirectUri());
  const url = `https://${COGNITO_DOMAIN}/oauth2/authorize?identity_provider=Google&redirect_uri=${redirectUri}&response_type=code&client_id=${COGNITO_CLIENT_ID}&scope=email+openid+profile`;
  window.location.href = url;
}

export async function exchangeCodeForTokens(code: string): Promise<void> {
  if (!COGNITO_DOMAIN) {
    throw new Error("COGNITO_DOMAIN is not configured");
  }
  const endpoint = `https://${COGNITO_DOMAIN}/oauth2/token`;
  const redirectUri = getRedirectUri();
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: COGNITO_CLIENT_ID,
    code,
    redirect_uri: redirectUri,
  });

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error_description || data.error || "Failed to exchange authorization code");
  }

  if (data.id_token) {
    localStorage.setItem(ID_TOKEN_KEY, data.id_token);
    localStorage.setItem("peach_auth_provider", "google");
  }
  if (data.access_token) {
    localStorage.setItem(ACCESS_TOKEN_KEY, data.access_token);
  }
  if (data.refresh_token) {
    localStorage.setItem(REFRESH_TOKEN_KEY, data.refresh_token);
  }
}

export interface SessionUser {
  name: string;
  email: string;
  sub: string;
  provider: "google" | "password";
}

export async function signIn(email: string, password: string): Promise<void> {
  const endpoint = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth",
    },
    body: JSON.stringify({
      AuthFlow: "USER_PASSWORD_AUTH",
      ClientId: COGNITO_CLIENT_ID,
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password,
      },
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.message || data.__type || "Authentication failed");
  }

  if (data.AuthenticationResult) {
    localStorage.setItem(ID_TOKEN_KEY, data.AuthenticationResult.IdToken);
    localStorage.setItem(ACCESS_TOKEN_KEY, data.AuthenticationResult.AccessToken);
    localStorage.setItem("peach_auth_provider", "password");
    if (data.AuthenticationResult.RefreshToken) {
      localStorage.setItem(REFRESH_TOKEN_KEY, data.AuthenticationResult.RefreshToken);
    }
  }
}

export async function signUp(email: string, password: string, name?: string): Promise<void> {
  const endpoint = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/`;
  const attributes = [{ Name: "email", Value: email }];
  if (name) attributes.push({ Name: "name", Value: name });

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": "AWSCognitoIdentityProviderService.SignUp",
    },
    body: JSON.stringify({
      ClientId: COGNITO_CLIENT_ID,
      Username: email,
      Password: password,
      UserAttributes: attributes,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.message || data.__type || "Sign up failed");
  }
}

export async function confirmSignUp(email: string, code: string): Promise<void> {
  const endpoint = `https://cognito-idp.${COGNITO_REGION}.amazonaws.com/`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": "AWSCognitoIdentityProviderService.ConfirmSignUp",
    },
    body: JSON.stringify({
      ClientId: COGNITO_CLIENT_ID,
      Username: email,
      ConfirmationCode: code,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.message || data.__type || "Confirmation failed");
  }
}

export async function getIdToken(): Promise<string | null> {
  if (typeof window === "undefined") {
    return null;
  }
  return localStorage.getItem(ID_TOKEN_KEY);
}

export function setIdToken(token: string): void {
  if (typeof window !== "undefined") {
    localStorage.setItem(ID_TOKEN_KEY, token);
  }
}

export function useSession(): SessionUser | null {
  const [session, setSession] = useState<SessionUser | null>(null);

  useEffect(() => {
    try {
      const token = localStorage.getItem(ID_TOKEN_KEY);
      if (!token) return;
      const base64Url = token.split(".")[1];
      if (!base64Url) return;
      const base64 = base64Url.replace(/-/g, "+").replace(/_/g, "/");
      const jsonPayload = decodeURIComponent(
        atob(base64)
          .split("")
          .map((c) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
          .join("")
      );
      const data = JSON.parse(jsonPayload);
      const identities = data.identities || [];
      const hasGoogleIdentity = Array.isArray(identities) && identities.some(
        (id: any) => id.providerName?.toLowerCase() === "google" || id.providerType?.toLowerCase() === "google"
      );
      const username = String(data["cognito:username"] || "");
      const isGoogleUsername = username.toLowerCase().startsWith("google");
      const localProvider = typeof window !== "undefined" ? localStorage.getItem("peach_auth_provider") : null;

      const provider: "google" | "password" =
        hasGoogleIdentity || isGoogleUsername || localProvider === "google"
          ? "google"
          : "password";

      setSession({
        email: data.email || data["cognito:username"] || "User",
        name: data.name || data.email?.split("@")[0] || "User",
        sub: data.sub || "",
        provider,
      });
    } catch {
      setSession(null);
    }
  }, []);

  return session;
}

export function signOut(): void {
  if (typeof window !== "undefined") {
    localStorage.removeItem(ID_TOKEN_KEY);
    localStorage.removeItem(ACCESS_TOKEN_KEY);
    localStorage.removeItem(REFRESH_TOKEN_KEY);
    localStorage.removeItem("peach_auth_provider");
    window.location.href = "/";
  }
}

export function isAuthenticated(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return Boolean(localStorage.getItem(ID_TOKEN_KEY));
}
