#!/usr/bin/env node
// palette-check — the gate over every file this repository renders from the
// house palette.
//
//   palette-check.mjs [--render]
//
// The target list is palette-targets.json beside this file: for each entry the
// renderer is asked either to compare its output and record, or to write them.
// The palette revision and digest the outputs were rendered against are pinned
// in the same file, and every run passes both to the renderer, so a palette that
// moved under this repository fails the run instead of silently re-rendering.
//
// The renderer is the published program the same file names, run through npx at
// the pinned version: a local run and the CI run are then the same run, and no
// checkout of the renderer's repository is involved. COLOURWAY_BIN names a local
// executable instead, for a machine with no network or for work on the renderer
// itself.
//
// Exit codes, as the renderer's own contract defines them: 0 everything current,
// 1 drift (the output or its record differs from a fresh render), 2 the check
// could not run — a missing palette, an unreadable target list, or a render the
// renderer refused. A gate that reads 2 as "current" is broken, so 2 is never
// folded into 0.
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, "..", "..")
const manifestPath = join(here, "palette-targets.json")

const argv = process.argv.slice(2)
const render = argv.includes("--render")
const unknown = argv.filter((argument) => argument !== "--render")
if (unknown.length > 0) {
  console.error(`palette-check: unknown argument ${unknown[0]}`)
  console.error("usage: palette-check.sh [--render]")
  process.exit(2)
}

let manifest
try {
  manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
} catch (error) {
  console.error(`palette-check: ${manifestPath} could not be read: ${error.message}`)
  process.exit(2)
}
const pin = manifest.palette ?? {}
const tool = manifest.tool ?? {}
const targets = manifest.targets ?? []
if (typeof pin.sha256 !== "string" || typeof pin.revision !== "string" || typeof pin.path !== "string") {
  console.error(`palette-check: ${manifestPath} pins no palette path, revision and digest`)
  process.exit(2)
}
if (targets.length === 0) {
  console.error(`palette-check: ${manifestPath} lists no target — an empty list reads like a clean tree`)
  process.exit(2)
}

const palettePath = join(root, pin.path)
if (!existsSync(palettePath)) {
  console.error(`palette-check: no palette at ${palettePath} — THE CHECK DID NOT RUN`)
  process.exit(2)
}

/** The command a run uses: a local executable when one is named, the pinned package otherwise. */
function rendererPrefix() {
  const local = process.env.COLOURWAY_BIN
  if (local !== undefined && local !== "") return { command: local, prefix: [] }
  if (typeof tool.package !== "string" || typeof tool.version !== "string") {
    console.error(`palette-check: ${manifestPath} names no renderer package, and COLOURWAY_BIN is unset — THE CHECK DID NOT RUN`)
    process.exit(2)
  }
  return { command: "npx", prefix: ["--yes", `${tool.package}@${tool.version}`] }
}

const renderer = rendererPrefix()
let stale = 0
let refused = 0
for (const target of targets) {
  const args = [
    ...renderer.prefix,
    "--template",
    join(root, target.template),
    "--out",
    join(root, target.output),
    "--record",
    join(root, target.record),
    "--palette",
    palettePath,
    "--revision",
    pin.revision,
    "--expect-palette",
    pin.sha256,
  ]
  if (!render) args.push("--check")
  try {
    const printed = execFileSync(renderer.command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
    process.stdout.write(printed)
  } catch (error) {
    const printed = `${error.stdout ?? ""}${error.stderr ?? ""}`
    if (printed !== "") process.stdout.write(printed)
    if (error.status === 1) stale += 1
    else {
      refused += 1
      console.error(`palette-check: ${target.template} could not be rendered (exit ${error.status ?? "signal"})`)
    }
  }
}

if (render) {
  console.log(`palette: ${targets.length} target(s) rendered${refused === 0 ? "" : `, ${refused} refused`}`)
} else {
  console.log(`palette: ${targets.length} target(s) checked, ${stale} stale, ${refused} could not run`)
}
process.exit(refused > 0 ? 2 : stale > 0 ? 1 : 0)
