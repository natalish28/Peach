"use client";

import { LogOut } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { signOut, useSession } from "@/lib/auth";
import { cn } from "@/lib/utils";

const links = [
  { href: "/home", label: "Home" },
  { href: "/items", label: "Board" },
];

export function SiteHeader() {
  const pathname = usePathname();
  const router = useRouter();
  const session = useSession();

  return (
    <header className="sticky top-0 z-40 border-b border-border/70 bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 w-full max-w-5xl items-center gap-6 px-4 sm:px-8">
        <Link href={session ? "/home" : "/"} className="flex items-center gap-2">
          <span
            aria-hidden
            className="grid size-6 place-items-center rounded-md bg-foreground font-heading text-[13px] leading-none font-semibold text-background"
          >
            P
          </span>
          <span className="font-heading text-[15px] font-semibold tracking-tight">
            Peach
          </span>
        </Link>

        {session && (
          <nav className="flex items-center gap-1 text-sm">
            {links.map((link) => {
              const active = pathname.startsWith(link.href);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "rounded-md px-2.5 py-1.5 font-medium transition-colors",
                    active
                      ? "bg-accent text-foreground"
                      : "text-muted-foreground hover:bg-accent hover:text-foreground",
                  )}
                >
                  {link.label}
                </Link>
              );
            })}
          </nav>
        )}

        {session ? (
          <div className="ml-auto flex items-center gap-2 sm:gap-3">
            <div className="hidden sm:flex items-center gap-2">
              <span
                aria-hidden
                className="grid size-6 place-items-center rounded-full bg-orange-100 text-xs font-semibold text-orange-900"
              >
                {session.name.charAt(0).toUpperCase()}
              </span>
              <span className="text-xs font-medium text-foreground">
                {session.email}
              </span>
            </div>

            {/* Provider indicator badge */}
            {session.provider === "google" ? (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-blue-50 px-2.5 py-0.5 text-xs font-medium text-blue-700 border border-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:border-blue-800">
                <svg className="h-3 w-3" viewBox="0 0 24 24">
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
                Google
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-700 border border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700">
                🔑 Пароль
              </span>
            )}

            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                signOut();
              }}
              className="gap-1.5 hover:bg-destructive/10 hover:text-destructive hover:border-destructive/30"
            >
              <LogOut className="size-3.5" />
              <span>Вийти</span>
            </Button>
          </div>
        ) : pathname !== "/" ? (
          <div className="ml-auto flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => router.push("/")}
            >
              Увійти
            </Button>
          </div>
        ) : null}
      </div>
    </header>
  );
}
