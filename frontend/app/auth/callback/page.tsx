"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { exchangeCodeForTokens } from "@/lib/auth";

function CallbackHandler() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const code = searchParams.get("code");
    const errorParam = searchParams.get("error");
    const errorDescription = searchParams.get("error_description");

    if (errorParam) {
      setError(errorDescription || errorParam || "Authentication failed");
      return;
    }

    if (!code) {
      setError("No authorization code provided");
      return;
    }

    exchangeCodeForTokens(code)
      .then(() => {
        router.push("/items");
      })
      .catch((err: any) => {
        setError(err.message || "Failed to complete sign in");
      });
  }, [searchParams, router]);

  if (error) {
    return (
      <div className="mx-auto flex min-h-[60vh] max-w-md flex-col items-center justify-center p-4 text-center">
        <div className="mb-4 rounded-md bg-destructive/15 p-4 text-sm text-destructive font-medium">
          {error}
        </div>
        <a href="/" className="text-sm text-primary underline">
          Return to sign in
        </a>
      </div>
    );
  }

  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <p className="text-muted-foreground animate-pulse">Completing sign in with Google...</p>
    </div>
  );
}

export default function AuthCallbackPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-[60vh] items-center justify-center">
          <p className="text-muted-foreground">Loading...</p>
        </div>
      }
    >
      <CallbackHandler />
    </Suspense>
  );
}

