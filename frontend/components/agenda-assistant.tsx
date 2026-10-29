"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Plus, Sparkles, Trash2 } from "lucide-react";
import { useRef, useState } from "react";
import { toast } from "sonner";

import { PageHeader } from "@/components/page-header";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import {
  emptyAgendaForm,
  formFromParsed,
  suggestedKeys,
  toAgendaInput,
  type AgendaFormState,
} from "@/lib/agenda-form";
import { api, type AiSuggestion } from "@/lib/api";
import { MAX_PASTE_CHARS, parseAgenda } from "@/lib/parser";

/** A labelled input that wears a "suggested" badge until the user touches it. */
function Suggested({
  label,
  fieldKey,
  suggested,
  children,
}: {
  label: string;
  fieldKey: string;
  suggested: Set<string>;
  children: React.ReactNode;
}) {
  return (
    <label className="grid gap-1 text-sm">
      <span className="flex items-center gap-2 font-medium">
        {label}
        {suggested.has(fieldKey) && (
          <Badge variant="secondary" className="text-[10px]">
            suggested
          </Badge>
        )}
      </span>
      {children}
    </label>
  );
}

export function AgendaAssistant() {
  const queryClient = useQueryClient();
  const [text, setText] = useState("");
  const [form, setForm] = useState<AgendaFormState>(emptyAgendaForm);
  const [suggestion, setSuggestion] = useState<AiSuggestion | null>(null);
  const [suggested, setSuggested] = useState<Set<string>>(new Set());
  const [parseError, setParseError] = useState<string | null>(null);
  const [parsing, setParsing] = useState(false);
  const abort = useRef<AbortController | null>(null);

  const agendas = useQuery({
    queryKey: ["agendas"],
    queryFn: () => api.listAgendas(),
  });

  const touch = (key: string) =>
    setSuggested((prev) => {
      if (!prev.has(key)) return prev;
      const next = new Set(prev);
      next.delete(key);
      return next;
    });

  function edit(key: string, update: (f: AgendaFormState) => AgendaFormState) {
    setForm(update);
    touch(key);
  }

  async function onParse() {
    const controller = new AbortController();
    abort.current = controller;
    setParsing(true);
    setParseError(null);
    try {
      const result = await parseAgenda(text, controller.signal);
      const filled = formFromParsed(result.agenda);
      setSuggestion(result);
      setForm(filled);
      setSuggested(suggestedKeys(filled));
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      setParseError(
        error instanceof Error
          ? error.message
          : "The parser is unavailable right now.",
      );
    } finally {
      setParsing(false);
      abort.current = null;
    }
  }

  const save = useMutation({
    mutationFn: () => api.createAgenda(toAgendaInput(form, suggestion)),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["agendas"] });
      toast.success("Agenda saved");
      setText("");
      setForm(emptyAgendaForm);
      setSuggestion(null);
      setSuggested(new Set());
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const canSave =
    form.title.trim() !== "" && form.items.some((i) => i.topic.trim() !== "");

  return (
    <div className="mx-auto grid w-full max-w-5xl gap-8 px-4 py-10 sm:px-8">
      <PageHeader
        icon="📋"
        title="Agendas"
        description="Paste an email or chat message: the model suggests an agenda, you check it and save."
      />

      <section className="grid gap-3" aria-labelledby="paste-heading">
        <h2 id="paste-heading" className="font-heading text-lg font-semibold">
          Paste an agenda
        </h2>
        <Textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          maxLength={MAX_PASTE_CHARS}
          placeholder="Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв …"
          className="min-h-32"
          disabled={parsing}
        />
        <div className="flex items-center gap-3">
          <Button onClick={onParse} disabled={parsing || text.trim() === ""}>
            {parsing ? <Loader2 className="animate-spin" /> : <Sparkles />}
            Parse
          </Button>
          {parsing && (
            <>
              <span role="status" className="text-sm text-muted-foreground">
                Reading your text… this takes a few seconds.
              </span>
              <Button variant="outline" onClick={() => abort.current?.abort()}>
                Cancel
              </Button>
            </>
          )}
          <span className="ml-auto text-xs text-muted-foreground">
            {text.length.toLocaleString("en")} /{" "}
            {MAX_PASTE_CHARS.toLocaleString("en")}
          </span>
        </div>
        {parseError && (
          <Alert variant="destructive">
            <AlertDescription>
              {parseError} You can always fill in the agenda by hand below.
            </AlertDescription>
          </Alert>
        )}
      </section>

      <section className="grid gap-4" aria-labelledby="form-heading">
        <h2 id="form-heading" className="font-heading text-lg font-semibold">
          {suggestion ? "Check the suggestion" : "Add agenda"}
        </h2>
        <form
          className="grid gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate();
          }}
        >
          <Suggested label="Title" fieldKey="title" suggested={suggested}>
            <Input
              value={form.title}
              onChange={(e) =>
                edit("title", (f) => ({ ...f, title: e.target.value }))
              }
            />
          </Suggested>
          <div className="grid gap-4 sm:grid-cols-2">
            <Suggested
              label="Starts"
              fieldKey="starts_at"
              suggested={suggested}
            >
              <Input
                type="datetime-local"
                value={form.starts_at}
                onChange={(e) =>
                  edit("starts_at", (f) => ({
                    ...f,
                    starts_at: e.target.value,
                  }))
                }
              />
            </Suggested>
            <Suggested
              label="Duration, min"
              fieldKey="duration_minutes"
              suggested={suggested}
            >
              <Input
                type="number"
                min={1}
                max={600}
                value={form.duration_minutes}
                onChange={(e) =>
                  edit("duration_minutes", (f) => ({
                    ...f,
                    duration_minutes: e.target.value,
                  }))
                }
              />
            </Suggested>
          </div>

          <fieldset className="grid gap-3">
            <legend className="mb-1 text-sm font-medium">Topics</legend>
            {form.items.map((item, n) => (
              <div
                key={n}
                className="grid gap-2 sm:grid-cols-[1fr_10rem_6rem_auto]"
              >
                <Suggested
                  label="Topic"
                  fieldKey={`items.${n}.topic`}
                  suggested={suggested}
                >
                  <Input
                    value={item.topic}
                    onChange={(e) =>
                      edit(`items.${n}.topic`, (f) => ({
                        ...f,
                        items: f.items.map((x, i) =>
                          i === n ? { ...x, topic: e.target.value } : x,
                        ),
                      }))
                    }
                  />
                </Suggested>
                <Suggested
                  label="Owner"
                  fieldKey={`items.${n}.owner`}
                  suggested={suggested}
                >
                  <Input
                    value={item.owner}
                    onChange={(e) =>
                      edit(`items.${n}.owner`, (f) => ({
                        ...f,
                        items: f.items.map((x, i) =>
                          i === n ? { ...x, owner: e.target.value } : x,
                        ),
                      }))
                    }
                  />
                </Suggested>
                <Suggested
                  label="Min"
                  fieldKey={`items.${n}.minutes`}
                  suggested={suggested}
                >
                  <Input
                    type="number"
                    min={1}
                    max={480}
                    value={item.minutes}
                    onChange={(e) =>
                      edit(`items.${n}.minutes`, (f) => ({
                        ...f,
                        items: f.items.map((x, i) =>
                          i === n ? { ...x, minutes: e.target.value } : x,
                        ),
                      }))
                    }
                  />
                </Suggested>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="self-end"
                  aria-label="Remove topic"
                  disabled={form.items.length === 1}
                  onClick={() =>
                    setForm((f) => ({
                      ...f,
                      items: f.items.filter((_, i) => i !== n),
                    }))
                  }
                >
                  <Trash2 />
                </Button>
              </div>
            ))}
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="w-fit"
              onClick={() =>
                setForm((f) => ({
                  ...f,
                  items: [...f.items, { topic: "", owner: "", minutes: "" }],
                }))
              }
            >
              <Plus /> Add topic
            </Button>
          </fieldset>

          {form.actions.length > 0 && (
            <fieldset className="grid gap-3">
              <legend className="mb-1 text-sm font-medium">Action items</legend>
              {form.actions.map((action, n) => (
                <div
                  key={n}
                  className="grid gap-2 sm:grid-cols-[1fr_10rem_10rem_auto]"
                >
                  <Suggested
                    label="Task"
                    fieldKey={`actions.${n}.task`}
                    suggested={suggested}
                  >
                    <Input
                      value={action.task}
                      onChange={(e) =>
                        edit(`actions.${n}.task`, (f) => ({
                          ...f,
                          actions: f.actions.map((x, i) =>
                            i === n ? { ...x, task: e.target.value } : x,
                          ),
                        }))
                      }
                    />
                  </Suggested>
                  <Suggested
                    label="Owner"
                    fieldKey={`actions.${n}.owner`}
                    suggested={suggested}
                  >
                    <Input
                      value={action.owner}
                      onChange={(e) =>
                        edit(`actions.${n}.owner`, (f) => ({
                          ...f,
                          actions: f.actions.map((x, i) =>
                            i === n ? { ...x, owner: e.target.value } : x,
                          ),
                        }))
                      }
                    />
                  </Suggested>
                  <Suggested
                    label="Due"
                    fieldKey={`actions.${n}.due`}
                    suggested={suggested}
                  >
                    <Input
                      type="date"
                      value={action.due}
                      onChange={(e) =>
                        edit(`actions.${n}.due`, (f) => ({
                          ...f,
                          actions: f.actions.map((x, i) =>
                            i === n ? { ...x, due: e.target.value } : x,
                          ),
                        }))
                      }
                    />
                  </Suggested>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="self-end"
                    aria-label="Remove action item"
                    onClick={() =>
                      setForm((f) => ({
                        ...f,
                        actions: f.actions.filter((_, i) => i !== n),
                      }))
                    }
                  >
                    <Trash2 />
                  </Button>
                </div>
              ))}
            </fieldset>
          )}

          <div>
            <Button type="submit" disabled={!canSave || save.isPending}>
              {save.isPending && <Loader2 className="animate-spin" />}
              Save
            </Button>
          </div>
        </form>
      </section>

      <section className="grid gap-3" aria-labelledby="saved-heading">
        <h2 id="saved-heading" className="font-heading text-lg font-semibold">
          Saved agendas
        </h2>
        {agendas.isPending && <Skeleton className="h-16 w-full" />}
        {agendas.isError && (
          <Alert variant="destructive">
            <AlertDescription>Could not load agendas.</AlertDescription>
          </Alert>
        )}
        {agendas.data?.agendas.length === 0 && (
          <p className="text-sm text-muted-foreground">Nothing saved yet.</p>
        )}
        <ul className="grid gap-2">
          {agendas.data?.agendas.map((a) => (
            <li key={a.id} className="rounded-lg border p-3 text-sm">
              <div className="flex items-center gap-2 font-medium">
                {a.title}
                {a.ai_suggestion && (
                  <Badge variant="secondary">AI-assisted</Badge>
                )}
              </div>
              <ol className="mt-1 list-decimal pl-5 text-muted-foreground">
                {a.items.map((i, n) => (
                  <li key={n}>
                    {i.topic}
                    {i.owner ? ` — ${i.owner}` : ""}
                    {i.minutes ? `, ${i.minutes} min` : ""}
                  </li>
                ))}
              </ol>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
