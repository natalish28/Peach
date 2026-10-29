import { describe, expect, it } from "vitest";

import {
  formFromParsed,
  suggestedKeys,
  toAgendaInput,
} from "@/lib/agenda-form";
import type { AiSuggestion } from "@/lib/api";
import { clientToday, parseErrorMessage } from "@/lib/parser";

const suggestion: AiSuggestion = {
  model: "anthropic.claude-opus-5-5",
  prompt_version: "agenda-v1",
  agenda: {
    title: "Синк по прайсингу",
    duration_minutes: 45,
    language: "uk",
    items: [
      { topic: "нові тарифи Pro", owner: "Олена", minutes: 15 },
      { topic: "річна знижка" },
    ],
    action_items: [{ task: "порівняння", owner: "Taras", due: "2026-10-30" }],
  },
};

describe("agenda form", () => {
  it("pre-fills the model's values and leaves the rest empty", () => {
    const form = formFromParsed(suggestion.agenda);
    expect(form.title).toBe("Синк по прайсингу");
    expect(form.starts_at).toBe("");
    expect(form.items[1]).toEqual({
      topic: "річна знижка",
      owner: "",
      minutes: "",
    });
  });

  it("marks only the filled fields as suggested", () => {
    const keys = suggestedKeys(formFromParsed(suggestion.agenda));
    expect(keys.has("title")).toBe(true);
    expect(keys.has("items.0.owner")).toBe(true);
    expect(keys.has("items.1.owner")).toBe(false);
    expect(keys.has("starts_at")).toBe(false);
  });

  it("saves the user's corrections together with the original suggestion", () => {
    const form = formFromParsed(suggestion.agenda);
    form.items[0].owner = "Olena";
    const payload = toAgendaInput(form, suggestion);
    expect(payload.items[0].owner).toBe("Olena");
    expect(payload.items[1].minutes).toBeNull();
    expect(payload.ai_suggestion?.agenda.items[0].owner).toBe("Олена");
    expect(payload.ai_suggestion?.prompt_version).toBe("agenda-v1");
  });

  it("drops blank rows and sends no suggestion for a hand-typed agenda", () => {
    const payload = toAgendaInput(
      {
        title: " Weekly ",
        starts_at: "",
        duration_minutes: "30",
        items: [
          { topic: "Plan", owner: "", minutes: "" },
          { topic: " ", owner: "", minutes: "" },
        ],
        actions: [],
      },
      null,
    );
    expect(payload.title).toBe("Weekly");
    expect(payload.items).toHaveLength(1);
    expect(payload.duration_minutes).toBe(30);
    expect(payload.ai_suggestion).toBeNull();
  });
});

describe("parser client", () => {
  it("gives each failure its own message", () => {
    const messages = [401, 413, 422, 429, 0, 502].map(parseErrorMessage);
    expect(new Set(messages).size).toBe(messages.length);
  });

  it("sends the user's local date and time zone", () => {
    const { today, tz } = clientToday(new Date("2026-10-28T12:00:00Z"));
    expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(tz.length).toBeGreaterThan(0);
  });
});
