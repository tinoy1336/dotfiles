/**
 * house.template.ts — the agent's own theme, rendered to house.json.
 *
 * pi reads a user theme from this directory as JSON, and the format has no
 * comment syntax and carries no alpha, so every value here is the token's solid
 * form: the declared composite where the palette has one, otherwise the token
 * painted over the surface base. That is also why this file carries no
 * generated-file banner — the record beside it, and the README, say where it
 * comes from.
 *
 * pi asks for far more roles than the palette names. Each key below is either a
 * token read straight through, the palette's `syntax.*` family, or a composite
 * this file has to compose:
 *
 *   - `toolSuccessBg` is the only role the palette has no token for: it is the
 *     success colour at the alpha the destructive fill uses, so the two state
 *     backgrounds read as a pair.
 */

type Token = { hex?: string; alpha?: number; solid?: string }
type Context = {
  palette: { find(name: string): Token }
  colour: {
    parseHex(hex: string): { r: number; g: number; b: number }
    toHex(rgb: { r: number; g: number; b: number }): string
    compositeOver(hex: string, alpha: number, baseHex: string): string
  }
  provenance: { palette: { sha256: string; revision: string }; template: { sha256: string } }
}

const SCHEMA = "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json"

function value(context: Context, name: string): string {
  const token = context.palette.find(name)
  const resolved = token.solid ?? token.hex
  if (resolved === undefined) throw new Error(`${name} carries no colour`)
  return resolved
}

/**
 * `derive:state-background:<token>` — that token at the alpha the destructive
 * fill uses, painted over the surface base. The only shape here the palette
 * cannot name, and the key order above keeps the state backgrounds together.
 */
function stateBackground(context: Context, name: string): string {
  const token = context.palette.find(name)
  if (token.hex === undefined) throw new Error(`${name} carries no colour`)
  const fill = context.palette.find("interaction.danger-fill")
  if (fill.alpha === undefined) throw new Error("interaction.danger-fill carries no alpha")
  return context.colour.compositeOver(token.hex, fill.alpha, value(context, "surface.base"))
}

function resolve(context: Context, source: string): string {
  const derived = source.split(":")
  if (derived[0] === "derive" && derived[1] === "state-background" && derived[2] !== undefined) {
    return stateBackground(context, derived[2])
  }
  return value(context, source)
}

const COLOURS: [string, string][] = [
  ["accent", "accent.primary"],
  ["border", "border.hairline"],
  ["borderAccent", "accent.primary"],
  ["borderMuted", "border.strong"],
  ["success", "state.success"],
  ["error", "state.error"],
  ["warning", "state.warning"],
  ["muted", "text.muted"],
  ["dim", "text.faint-solid"],
  ["text", "text.primary"],
  ["thinkingText", "text.muted"],

  ["selectedBg", "interaction.accent-fill"],
  ["scrollbarTrack", "border.hairline"],
  ["scrollbarThumb", "text.faint-solid"],
  ["searchMatchBg", "interaction.selection-text"],
  ["searchMatchText", "text.strong"],
  ["userMessageBg", "interaction.selection-row"],
  ["userMessageText", "text.primary"],
  ["customMessageBg", "interaction.selection-menu"],
  ["customMessageText", "text.primary"],
  ["customMessageLabel", "accent.soft"],
  ["toolPendingBg", "interaction.wash"],
  ["toolSuccessBg", "derive:state-background:state.success"],
  ["toolErrorBg", "interaction.danger-fill"],
  ["toolTitle", "accent.primary"],
  ["toolOutput", "text.secondary"],

  ["mdHeading", "text.strong"],
  ["mdLink", "accent.primary"],
  ["mdLinkUrl", "text.faint-solid"],
  ["mdCode", "accent.secondary"],
  ["mdCodeBlock", "state.success"],
  ["mdCodeBlockBorder", "border.hairline"],
  ["mdQuote", "text.secondary"],
  ["mdQuoteBorder", "border.strong"],
  ["mdHr", "border.strong"],
  ["mdListBullet", "accent.primary"],

  ["toolDiffAdded", "state.success"],
  ["toolDiffRemoved", "state.error"],
  ["toolDiffContext", "text.faint-solid"],
]

/** The keys pi asks for after the syntax family, in the order it lists them. */
const AFTER_SYNTAX: [string, string][] = [
  ["thinkingOff", "text.faint-solid"],
  ["thinkingMinimal", "text.muted"],
  ["thinkingLow", "text.secondary"],
  ["thinkingMedium", "text.primary"],
  ["thinkingHigh", "text.strong"],
  ["thinkingXhigh", "accent.primary"],
  ["thinkingMax", "accent.soft"],

  ["bashMode", "state.success"],
]

/** The nine syntax roles, named in pi's vocabulary rather than the palette's. */
const SYNTAX: [string, string][] = [
  ["syntaxComment", "comment"],
  ["syntaxKeyword", "keyword"],
  ["syntaxFunction", "function"],
  ["syntaxVariable", "variable"],
  ["syntaxString", "string"],
  ["syntaxNumber", "number"],
  ["syntaxType", "type"],
  ["syntaxOperator", "operator"],
  ["syntaxPunctuation", "punctuation"],
]

const EXPORT: [string, string][] = [
  ["pageBg", "surface.base"],
  ["cardBg", "surface.view"],
  ["infoBg", "interaction.wash"],
]

export default {
  render(context: Context): string {
    const colors: Record<string, string> = {}
    for (const [key, source] of COLOURS) colors[key] = resolve(context, source)
    for (const [key, role] of SYNTAX) colors[key] = value(context, `syntax.${role}`)
    for (const [key, source] of AFTER_SYNTAX) colors[key] = resolve(context, source)
    const exported: Record<string, string> = {}
    for (const [key, source] of EXPORT) exported[key] = value(context, source)
    return `${JSON.stringify({ $schema: SCHEMA, name: "house", colors, export: exported }, null, 2)}\n`
  },
}
