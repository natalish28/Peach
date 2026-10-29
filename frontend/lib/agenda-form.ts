import type { AgendaInput, AiSuggestion, ParsedAgenda } from "@/lib/api";

export type AgendaFormItem = { topic: string; owner: string; minutes: string };
export type AgendaFormAction = { task: string; owner: string; due: string };

export type AgendaFormState = {
  title: string;
  starts_at: string; // <input type="datetime-local">: local time, no offset
  duration_minutes: string;
  items: AgendaFormItem[];
  actions: AgendaFormAction[];
};

export const emptyAgendaForm: AgendaFormState = {
  title: "",
  starts_at: "",
  duration_minutes: "",
  items: [{ topic: "", owner: "", minutes: "" }],
  actions: [],
};

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

/** An ISO timestamp as the local "YYYY-MM-DDTHH:mm" a datetime-local input wants. */
export function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Pre-fill the form from a suggestion. Empty stays empty. */
export function formFromParsed(parsed: ParsedAgenda): AgendaFormState {
  return {
    title: parsed.title ?? "",
    starts_at: toLocalInput(parsed.starts_at),
    duration_minutes: parsed.duration_minutes?.toString() ?? "",
    items: parsed.items.map((i) => ({
      topic: i.topic,
      owner: i.owner ?? "",
      minutes: i.minutes?.toString() ?? "",
    })),
    actions: parsed.action_items.map((a) => ({
      task: a.task,
      owner: a.owner ?? "",
      due: a.due ?? "",
    })),
  };
}

/** Keys of the filled fields, so each can wear a "suggested" badge until touched. */
export function suggestedKeys(form: AgendaFormState): Set<string> {
  const keys = new Set<string>();
  const add = (key: string, value: string) => value && keys.add(key);
  add("title", form.title);
  add("starts_at", form.starts_at);
  add("duration_minutes", form.duration_minutes);
  form.items.forEach((i, n) => {
    add(`items.${n}.topic`, i.topic);
    add(`items.${n}.owner`, i.owner);
    add(`items.${n}.minutes`, i.minutes);
  });
  form.actions.forEach((a, n) => {
    add(`actions.${n}.task`, a.task);
    add(`actions.${n}.owner`, a.owner);
    add(`actions.${n}.due`, a.due);
  });
  return keys;
}

const orNull = (v: string) => (v.trim() === "" ? null : v.trim());
const intOrNull = (v: string) => (v.trim() === "" ? null : Number(v));

/** The payload for POST /agendas: the user's final values plus what the model suggested. */
export function toAgendaInput(
  form: AgendaFormState,
  suggestion: AiSuggestion | null,
): AgendaInput {
  return {
    title: form.title.trim(),
    starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
    duration_minutes: intOrNull(form.duration_minutes),
    items: form.items
      .filter((i) => i.topic.trim() !== "")
      .map((i) => ({
        topic: i.topic.trim(),
        owner: orNull(i.owner),
        minutes: intOrNull(i.minutes),
      })),
    action_items: form.actions
      .filter((a) => a.task.trim() !== "")
      .map((a) => ({
        task: a.task.trim(),
        owner: orNull(a.owner),
        due: orNull(a.due),
      })),
    ai_suggestion: suggestion,
  };
}
