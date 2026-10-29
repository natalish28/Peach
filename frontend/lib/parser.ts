import { z } from "zod";

import { getIdToken } from "@/lib/auth";
import { aiSuggestionSchema, ApiError, type AiSuggestion } from "@/lib/api";

/** The agenda-parser Lambda's function URL (baked in at build time). It only
 *  ever suggests: saving goes through the normal API. */
const PARSER_URL = process.env.NEXT_PUBLIC_PARSER_URL ?? "";

export const MAX_PASTE_CHARS = 10_000;

const responseSchema = z.object({
  agenda: aiSuggestionSchema.shape.agenda,
  model: z.string(),
  prompt_version: z.string(),
});

/** The user's "Monday" is in their time zone, not the Lambda's (UTC). */
export function clientToday(now = new Date()): { today: string; tz: string } {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return { today: now.toLocaleDateString("en-CA", { timeZone: tz }), tz };
}

/** A message for each way a parse can fail, so the user knows what to do. */
export function parseErrorMessage(status: number): string {
  switch (status) {
    case 401:
      return "Your session expired. Sign in again.";
    case 413:
      return `The text is too long (max ${MAX_PASTE_CHARS.toLocaleString("en")} characters).`;
    case 422:
      return "The model could not find an agenda in this text.";
    case 429:
      return "The service is busy. Try again in a minute.";
    case 0:
      return "Could not reach the parser. Check your connection.";
    default:
      return "The parser is unavailable right now.";
  }
}

export async function parseAgenda(
  text: string,
  signal: AbortSignal,
): Promise<AiSuggestion> {
  if (!PARSER_URL)
    throw new ApiError(503, "The agenda parser is not deployed.");
  const token = await getIdToken();
  if (!token) throw new ApiError(401, parseErrorMessage(401));

  let response: Response;
  try {
    response = await fetch(PARSER_URL, {
      method: "POST",
      signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ text, ...clientToday() }),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError")
      throw error;
    throw new ApiError(0, parseErrorMessage(0));
  }
  if (!response.ok) {
    throw new ApiError(response.status, parseErrorMessage(response.status));
  }
  return responseSchema.parse(await response.json());
}
