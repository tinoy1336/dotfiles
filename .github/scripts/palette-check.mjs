#!/usr/bin/env node
// palette-check — the gate over every file this repository renders from the
// house palette.
//
//   palette-check.mjs --renderer <path> [--render]
//
// The target list is palette-targets.json beside this file: for each entry the
// renderer is asked either to compare its output and record, or to write them.
// The palette revision and digest the outputs were rendered against are pinned
// in the same file, and every run passes them to the renderer, so a palette that
// moved under this repository fails the run instead of silently re-rendering.
//
// Exit codes, as the renderer's own contract defines them: 0 everything current,
// 1 drift (the output or its record differs from a fresh render), 2 the check
// could not run — a missing renderer, an unreadable target list, or a render the
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
const argValue = (name) => {
  const index = argv.indexOf(name)
  return index === -1 ? undefined : argv[index + 1]
}
const renderer = argValue("--renderer")
const render = argv.includes("--render")
const usage = "usage: palette-check.sh <path-to-render> [--render]"

if (renderer === undefined || renderer === "") {
  console.error("palette-check: no renderer given — a run without one would report nothing")
  console.error(usage)
  process.exit(2)
}
if (!existsSync(renderer)) {
  console.error(`palette-check: ${renderer} does not exist — THE CHECK DID NOT RUN`)
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
const targets = manifest.targets ?? []
if (typeof pin.sha256 !== "string" || typeof pin.revision !== "string") {
  console.error(`palette-check: ${manifestPath} pins no palette revision and digest`)
  process.exit(2)
}
if (targets.length === 0) {
  console.error(`palette-check: ${manifestPath} lists no target — an empty list reads like a clean tree`)
  process.exit(2)
}

let stale = 0
let refused = 0
for (const target of targets) {
  const args = [
    "--template",
    join(root, target.template),
    "--out",
    join(root, target.output),
    "--record",
    join(root, target.record),
    "--revision",
    pin.revision,
    "--expect-palette",
    pin.sha256,
  ]
  if (!render) args.push("--check")
  try {
    const printed = execFileSync(renderer, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
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
