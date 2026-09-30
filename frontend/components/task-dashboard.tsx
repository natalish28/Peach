"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, Clock, ListTodo, Plus } from "lucide-react";

import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { api, type Item } from "@/lib/api";

export function TaskDashboard() {
  const { data, isPending } = useQuery({
    queryKey: ["items"],
    queryFn: () => api.listItems({ limit: 100 }),
  });

  const items = data?.items ?? [];
  const todoCount = items.filter((i) => i.status === "todo").length;
  const inProgressCount = items.filter((i) => i.status === "in_progress").length;
  const doneCount = items.filter((i) => i.status === "done").length;
  const total = items.length;
  const progressPct = total > 0 ? Math.round((doneCount / total) * 100) : 0;

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <PageHeader
        title="Dashboard"
        description="Overview of your tasks and board status"
        action={
          <Button asChild>
            <Link href="/items">
              <Plus className="mr-2 h-4 w-4" /> Go to Board
            </Link>
          </Button>
        }
      />

      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Total Tasks</CardTitle>
            <ListTodo className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            {isPending ? <Skeleton className="h-8 w-16" /> : <div className="text-2xl font-bold">{total}</div>}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">To Do</CardTitle>
            <Clock className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            {isPending ? <Skeleton className="h-8 w-16" /> : <div className="text-2xl font-bold">{todoCount}</div>}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">In Progress</CardTitle>
            <Clock className="h-4 w-4 text-yellow-500" />
          </CardHeader>
          <CardContent>
            {isPending ? <Skeleton className="h-8 w-16" /> : <div className="text-2xl font-bold">{inProgressCount}</div>}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Completed</CardTitle>
            <CheckCircle2 className="h-4 w-4 text-green-500" />
          </CardHeader>
          <CardContent>
            {isPending ? <Skeleton className="h-8 w-16" /> : <div className="text-2xl font-bold">{doneCount} ({progressPct}%)</div>}
          </CardContent>
        </Card>
      </div>

      <div className="mt-8">
        <Card>
          <CardHeader>
            <CardTitle>Recent Tasks</CardTitle>
          </CardHeader>
          <CardContent>
            {isPending ? (
              <div className="space-y-2">
                <Skeleton className="h-6 w-full" />
                <Skeleton className="h-6 w-full" />
              </div>
            ) : items.length === 0 ? (
              <div className="py-6 text-center text-sm text-muted-foreground">
                No tasks yet. <Link href="/items" className="text-primary underline">Create your first task on the board!</Link>
              </div>
            ) : (
              <div className="divide-y divide-border">
                {items.slice(0, 5).map((item) => (
                  <div key={item.id} className="flex items-center justify-between py-3">
                    <div>
                      <p className="font-medium">{item.name}</p>
                      {item.description && <p className="text-xs text-muted-foreground">{item.description}</p>}
                    </div>
                    <span className="rounded-full bg-secondary px-2.5 py-0.5 text-xs font-semibold capitalize">
                      {item.status.replace("_", " ")}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
