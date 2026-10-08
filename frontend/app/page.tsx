"use client";

import { useEffect, useState } from "react";
import { ItemBoard } from "@/components/item-board";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  confirmSignUp,
  isAuthenticated,
  signIn,
  signUp,
  signInWithGoogle,
  COGNITO_GOOGLE_ENABLED,
} from "@/lib/auth";

export default function RootPage() {
  const [authed, setAuthed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [mode, setMode] = useState<"login" | "signup" | "confirm">("login");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [code, setCode] = useState("");

  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setAuthed(isAuthenticated());
    setLoading(false);
  }, []);

  async function handleLogin(e?: React.FormEvent) {
    if (e) e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await signIn(email, password);
      setAuthed(true);
    } catch (err: any) {
      setError(err.message || "Failed to sign in");
    } finally {
      setBusy(false);
    }
  }

  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await signUp(email, password, name);
      setMode("confirm");
    } catch (err: any) {
      setError(err.message || "Failed to sign up");
    } finally {
      setBusy(false);
    }
  }

  async function handleConfirm(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await confirmSignUp(email, code);
      await signIn(email, password);
      setAuthed(true);
    } catch (err: any) {
      setError(err.message || "Verification code failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleDemoLogin() {
    setEmail("test@peach.app");
    setPassword("Peach2026!");
    setError(null);
    setBusy(true);
    try {
      await signIn("test@peach.app", "Peach2026!");
      setAuthed(true);
    } catch (err: any) {
      setError(err.message || "Demo login failed");
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <p className="text-muted-foreground">Loading Peach...</p>
      </div>
    );
  }

  if (authed) {
    return <ItemBoard />;
  }

  return (
    <div className="mx-auto flex min-h-[80vh] max-w-md flex-col justify-center px-4 py-12">
      <Card className="w-full shadow-lg border border-border">
        <CardHeader className="text-center">
          <div className="mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-xl bg-orange-100 text-2xl">
            🍑
          </div>
          <CardTitle className="text-2xl font-bold tracking-tight">Peach Task Manager</CardTitle>
          <CardDescription>
            {mode === "login" && "Sign in to manage your tasks with Amazon Cognito"}
            {mode === "signup" && "Create an account in Amazon Cognito"}
            {mode === "confirm" && `Enter the verification code sent to ${email}`}
          </CardDescription>
        </CardHeader>

        <CardContent>
          {error && (
            <div className="mb-4 rounded-md bg-destructive/15 p-3 text-sm text-destructive font-medium">
              {error}
            </div>
          )}

          {mode === "login" && (
            <form onSubmit={handleLogin} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Email</label>
                <Input
                  type="email"
                  required
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Password</label>
                <Input
                  type="password"
                  required
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
              </div>

              <Button type="submit" className="w-full" disabled={busy}>
                {busy ? "Signing in..." : "Sign In"}
              </Button>

              {COGNITO_GOOGLE_ENABLED && (
                <>
                  <div className="relative my-4 text-center text-xs text-muted-foreground">
                    <span className="bg-card px-2">or continue with</span>
                  </div>
                  <Button
                    type="button"
                    variant="outline"
                    className="w-full flex items-center justify-center gap-2"
                    onClick={() => {
                      try {
                        signInWithGoogle();
                      } catch (err: any) {
                        setError(err.message || "Google sign-in failed");
                      }
                    }}
                    disabled={busy}
                  >
                    <svg className="h-4 w-4" viewBox="0 0 24 24">
                      <path
                        fill="#4285F4"
                        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                      />
                      <path
                        fill="#34A853"
                        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                      />
                      <path
                        fill="#FBBC05"
                        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"
                      />
                      <path
                        fill="#EA4335"
                        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"
                      />
                    </svg>
                    Sign in with Google
                  </Button>
                </>
              )}

              <div className="relative my-4 text-center text-xs text-muted-foreground">
                <span className="bg-card px-2">or for quick lab evaluation</span>
              </div>

              <Button
                type="button"
                variant="outline"
                className="w-full border-dashed"
                onClick={handleDemoLogin}
                disabled={busy}
              >
                🚀 Quick Demo Login (Student)
              </Button>
            </form>
          )}

          {mode === "signup" && (
            <form onSubmit={handleSignUp} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Name</label>
                <Input
                  type="text"
                  placeholder="Your Name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Email</label>
                <Input
                  type="email"
                  required
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Password</label>
                <Input
                  type="password"
                  required
                  minLength={8}
                  placeholder="At least 8 characters"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
              </div>

              <Button type="submit" className="w-full" disabled={busy}>
                {busy ? "Creating account..." : "Sign Up"}
              </Button>
            </form>
          )}

          {mode === "confirm" && (
            <form onSubmit={handleConfirm} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-foreground">Confirmation Code</label>
                <Input
                  type="text"
                  required
                  placeholder="123456"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                />
              </div>

              <Button type="submit" className="w-full" disabled={busy}>
                {busy ? "Verifying..." : "Confirm & Sign In"}
              </Button>
            </form>
          )}
        </CardContent>

        <CardFooter className="flex justify-center border-t py-3">
          {mode === "login" ? (
            <p className="text-xs text-muted-foreground">
              Don&apos;t have an account?{" "}
              <button
                type="button"
                className="font-medium text-primary underline"
                onClick={() => {
                  setError(null);
                  setMode("signup");
                }}
              >
                Sign Up
              </button>
            </p>
          ) : (
            <p className="text-xs text-muted-foreground">
              Already have an account?{" "}
              <button
                type="button"
                className="font-medium text-primary underline"
                onClick={() => {
                  setError(null);
                  setMode("login");
                }}
              >
                Sign In
              </button>
            </p>
          )}
        </CardFooter>
      </Card>
    </div>
  );
}
