/**
 * OneNote extension - drives the Microsoft OneNote desktop application on the Windows host
 * from Pi running inside WSL, over the OneNote COM automation interface.
 *
 * Why COM instead of Microsoft Graph: it needs no app registration, no API scope and no
 * admin consent, and it works against the user's already-signed-in desktop client. It is
 * also silent - the COM proxy launches OneNote without a visible window and never takes
 * focus, so it does not disturb whatever the user is doing.
 *
 * The bridge is a one-shot powershell.exe process per call (see bridge.ps1). A persistent
 * worker was considered and rejected: a warm `New-Object -ComObject OneNote.Application`
 * costs 6-11 ms, so process startup dominates and the extra lifecycle buys nothing.
 *
 * Every tool is exposed to codemode rather than declared directly, and returns both text for
 * the transcript and `structuredContent` for scripts. Reads are free; every write tool is
 * dry-run by default, and its dry run is a real bridge call that reports the exact change
 * set OneNote would receive rather than a locally guessed preview.
 */

import { execFile, execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext, ToolNamespace } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const execFileAsync = promisify(execFile);

const POWERSHELL = "powershell.exe";
const BRIDGE_PATH = join(dirname(fileURLToPath(import.meta.url)), "bridge.ps1");
const CALL_TIMEOUT_MS = 180_000;
const MAX_TEXT_CHARS = 40_000;
/** The largest image verified end to end was 5.4 MB of base64; cap well above that, not at it. */
const MAX_IMAGE_BYTES = 32 * 1024 * 1024;

/**
 * Every tool is reachable from codemode scripts and listed by the codemode tool, but is not
 * declared directly, so a session that is not doing OneNote work carries no extra tool list.
 */
const CODEMODE = "codemode" as const;

const READ_ONLY = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
const ADDITIVE = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false } as const;
/** Matches every existing paragraph in an outline if the resend is wrong, so treat it as destructive. */
const REWRITING = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false } as const;

const NAMESPACE: ToolNamespace = {
	name: "onenote",
	description: "Microsoft OneNote desktop notebooks on the Windows host, reached over COM (no Microsoft Graph)",
	instructions: [
		"These tools drive the Windows OneNote desktop client through its COM automation interface from WSL.",
		"They work with the user's own signed-in notebooks, so writes land in real notes that sync to SharePoint/OneDrive.",
		"",
		"Identifying a page: prefer pageId, taken from onenote_pages or onenote_search. When only names are known, pass",
		"notebook + section + page together; a section name that exists in several notebooks is rejected as ambiguous.",
		"",
		"Writing text: OneNote replaces an entire outline with whatever one:OEChildren the caller sends, so a paragraph",
		"omitted from that list is DELETED. That is why onenote_edit exists and why it resends each affected outline in",
		"full, echoing back OneNote's own XML for everything the caller is not changing. Never hand-build outline XML:",
		"use onenote_edit for changes inside an outline and onenote_append_lines for a new outline at the end of a page.",
		"",
		"New content must never carry an objectID: OneNote rejects an id it did not issue with 0x8004200E, and assigns",
		"ids itself for anything sent without one.",
		"",
		"Concurrency: there is no usable concurrency token here. lastModifiedTime does not advance when content is written",
		"through COM, and OneNote's hierarchy API can report a different value than the page itself, so comparing it refuses",
		"correct writes while detecting nothing. Appends cannot clobber a concurrent edit, and onenote_delete_page guards",
		"on the exact page name instead. lastModified is reported as informational only.",
	].join("\n"),
};

// --- transport --------------------------------------------------------------

interface WorkDir {
	/** Windows path, e.g. C:\Users\me\AppData\Local\Temp\pi-onenote */
	win: string;
	/** The same directory as a WSL path. */
	wsl: string;
}

let cachedWorkDir: WorkDir | undefined;
let callCounter = 0;

function resolveWorkDir(): WorkDir {
	if (cachedWorkDir) return cachedWorkDir;

	let raw: string;
	try {
		raw = execFileSync(POWERSHELL, ["-NoProfile", "-NonInteractive", "-Command", "[IO.Path]::GetTempPath()"], {
			encoding: "utf8",
			timeout: 30_000,
		});
	} catch (error) {
		throw new Error(
			`These tools need the Windows host: ${POWERSHELL} could not be run from WSL (${error instanceof Error ? error.message : String(error)})`,
		);
	}

	const winTemp = raw.replace(/[\r\n]/g, "").trim().replace(/[\\/]+$/, "");
	const win = `${winTemp}\\pi-onenote`;
	const drive = /^([A-Za-z]):[\\/](.*)$/.exec(win);
	if (!drive) {
		throw new Error(`Unsupported Windows temp path (expected a drive-letter path): ${win}`);
	}
	const wsl = `/mnt/${drive[1].toLowerCase()}/${drive[2].split("\\").join("/")}`;
	mkdirSync(wsl, { recursive: true });

	cachedWorkDir = { win, wsl };
	return cachedWorkDir;
}

function psQuote(value: string): string {
	return `'${value.replace(/'/g, "''")}'`;
}

async function callBridge(op: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<Record<string, unknown>> {
	const work = resolveWorkDir();
	const stem = `call-${++callCounter}`;
	const requestPath = join(work.wsl, `req-${stem}.json`);
	const responsePath = join(work.wsl, `resp-${stem}.json`);

	const request = { op, __script: readFileSync(BRIDGE_PATH, "utf8"), ...args };
	writeFileSync(requestPath, JSON.stringify(request), "utf8");
	rmSync(responsePath, { force: true });

	// The bootstrap is tiny because a Windows command line caps out near 32 K characters;
	// the bridge source and every payload travel through the UTF-8 request file instead.
	// Paths ride here rather than in environment variables because WSL interop does not
	// forward the Linux environment to Windows executables.
	const bootstrap = [
		"$ErrorActionPreference='Stop'",
		`$d=${psQuote(work.win)}`,
		`$f=${psQuote(stem)}`,
		'$i=[IO.File]::ReadAllText("$d\\req-$f.json",[Text.Encoding]::UTF8)|ConvertFrom-Json',
		"Invoke-Expression $i.__script",
		"",
	].join("\n");

	try {
		await execFileAsync(
			POWERSHELL,
			["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", Buffer.from(bootstrap, "utf16le").toString("base64")],
			{ maxBuffer: 128 * 1024 * 1024, timeout: CALL_TIMEOUT_MS, signal },
		);
	} catch (error) {
		const detail = (error as { stderr?: string; stdout?: string; message?: string });
		const text = (detail.stderr || detail.stdout || detail.message || "").trim();
		throw new Error(`OneNote bridge failed: ${text || "powershell.exe returned a non-zero exit code"}`);
	} finally {
		rmSync(requestPath, { force: true });
	}

	let raw: string;
	try {
		raw = readFileSync(responsePath, "utf8");
	} catch {
		throw new Error("OneNote bridge produced no response; the bridge script may have failed before it could report an error");
	} finally {
		rmSync(responsePath, { force: true });
	}

	const parsed = JSON.parse(raw.replace(/^\uFEFF/, "")) as
		| { ok: true; data: Record<string, unknown> }
		| { ok: false; error: string; code?: string };
	if (!parsed.ok) {
		throw new Error(`OneNote ${parsed.code ?? "error"}: ${parsed.error}`);
	}
	return parsed.data;
}

// --- output schemas ---------------------------------------------------------

const NumOrNull = Type.Union([Type.Number(), Type.Null()]);

const SectionSchema = Type.Object(
	{ id: Type.String(), name: Type.String(), path: Type.String() },
	{ additionalProperties: true },
);
const NotebookSchema = Type.Object(
	{ id: Type.String(), name: Type.String(), path: Type.String(), sections: Type.Array(SectionSchema) },
	{ additionalProperties: true },
);
const PageMetaSchema = Type.Object(
	{ id: Type.String(), name: Type.String(), level: Type.String(), created: Type.String() },
	{ additionalProperties: true },
);
const PageLineSchema = Type.Object(
	{
		index: Type.Number(),
		objectID: Type.String(),
		text: Type.String(),
		inTitle: Type.Boolean(),
		inTable: Type.Boolean(),
		hasImage: Type.Boolean(),
		hasTable: Type.Boolean(),
		hasInk: Type.Boolean(),
		list: Type.String(),
		depth: Type.Number(),
		outlineID: Type.String(),
		quickStyle: Type.String(),
		alignment: Type.String(),
	},
	{ additionalProperties: true },
);
const PageOutlineSchema = Type.Object(
	{
		objectID: Type.String(),
		x: NumOrNull,
		y: NumOrNull,
		z: NumOrNull,
		width: NumOrNull,
		height: NumOrNull,
		inTitle: Type.Boolean(),
		lineCount: Type.Number(),
	},
	{ additionalProperties: true },
);
const PageImageSchema = Type.Object(
	{
		objectID: Type.String(),
		format: Type.String(),
		alt: Type.String(),
		x: NumOrNull,
		y: NumOrNull,
		width: NumOrNull,
		height: NumOrNull,
		outlineID: Type.String(),
		embedded: Type.Boolean(),
		callbackID: Type.String(),
	},
	{ additionalProperties: true },
);
const PageTableSchema = Type.Object(
	{ objectID: Type.String(), rows: Type.Number(), columns: Type.Number(), outlineID: Type.String() },
	{ additionalProperties: true },
);
const PageSchema = Type.Object(
	{
		id: Type.String(),
		name: Type.String(),
		level: Type.String(),
		lang: Type.String(),
		created: Type.String(),
		lastModified: Type.String(),
		lines: Type.Array(PageLineSchema),
		outlines: Type.Array(PageOutlineSchema),
		images: Type.Array(PageImageSchema),
		tables: Type.Array(PageTableSchema),
		rawXml: Type.Optional(Type.String()),
	},
	{ additionalProperties: true },
);
/** Covers all three outcomes of a write, because a dry run is a success too. */
const WriteResultSchema = Type.Object(
	{
		status: Type.Union([Type.Literal("dry-run"), Type.Literal("applied"), Type.Literal("cancelled")]),
		preview: Type.Optional(Type.String()),
		page: Type.Optional(PageSchema),
	},
	{ additionalProperties: true },
);
const EditChangeSchema = Type.Object(
	{
		outlineId: Type.String(),
		changed: Type.Array(Type.Object({ objectID: Type.String(), before: Type.String(), after: Type.String() }, { additionalProperties: true })),
		removed: Type.Array(Type.Object({ objectID: Type.String(), text: Type.String() }, { additionalProperties: true })),
		after: Type.Array(Type.String()),
	},
	{ additionalProperties: true },
);

// --- rendering --------------------------------------------------------------

interface PageLine {
	index: number;
	objectID?: string;
	text: string;
	inTitle?: boolean;
	inTable?: boolean;
	hasImage?: boolean;
	hasTable?: boolean;
	hasInk?: boolean;
	list?: string;
	depth?: number;
	outlineID?: string;
}

interface EditChange {
	outlineId: string;
	changed?: Array<{ objectID: string; before: string; after: string }>;
	removed?: Array<{ objectID: string; text: string }>;
	after?: string[];
}

function asArray<T>(value: unknown): T[] {
	if (value === undefined || value === null) return [];
	return Array.isArray(value) ? (value as T[]) : [value as T];
}

function asString(value: unknown): string {
	return typeof value === "string" ? value : "";
}

function truncate(text: string): string {
	if (text.length <= MAX_TEXT_CHARS) return text;
	return `${text.slice(0, MAX_TEXT_CHARS)}\n... truncated at ${MAX_TEXT_CHARS} characters`;
}

function formatPage(page: Record<string, unknown>): string {
	const lines: string[] = [`page: ${asString(page.name)}`, `id: ${asString(page.id)}`, `lastModified: ${asString(page.lastModified)} (informational)`];

	const tables = asArray<Record<string, unknown>>(page.tables);
	for (const table of tables) {
		lines.push(`table ${asString(table.objectID)}: ${table.rows}x${table.columns} cells, in outline ${asString(table.outlineID) || "(page level)"}`);
	}

	const outlines = asArray<Record<string, unknown>>(page.outlines);
	for (const outline of outlines) {
		const geometry = outline.x !== null && outline.x !== undefined ? ` at (${outline.x},${outline.y})` : "";
		lines.push(`outline ${asString(outline.objectID)}${outline.inTitle ? " (title)" : ""}${geometry}, ${outline.lineCount} paragraph(s)`);
	}

	const images = asArray<Record<string, unknown>>(page.images);
	for (const image of images) {
		const size = image.width ? ` ${Math.round(Number(image.width))}x${Math.round(Number(image.height))}` : "";
		lines.push(
			`image${size}${asString(image.alt) ? ` alt="${asString(image.alt)}"` : ""} in outline ${asString(image.outlineID) || "(page level)"}${image.embedded ? "" : " - NO BITS"}`,
		);
	}

	lines.push("content:");
	for (const line of asArray<PageLine>(page.lines)) {
		const marks: string[] = [];
		if (line.inTitle) marks.push("title");
		if (line.inTable) marks.push("table-cell");
		if (line.hasTable) marks.push("table");
		if (line.hasImage) marks.push("image");
		if (line.hasInk) marks.push("ink");
		if (line.list) marks.push(line.list);
		if (line.depth) marks.push(`depth=${line.depth}`);

		const indent = "  ".repeat(Math.min(line.depth ?? 0, 6));
		const text = line.text.includes("\n") ? line.text.replace(/\n/g, " / ") : line.text;
		const suffix = [marks.length ? `[${marks.join(",")}]` : "", line.objectID ? `oe=${line.objectID}` : ""].filter(Boolean).join(" ");
		lines.push(`  [${line.index}] ${indent}${text || "(no text)"}${suffix ? `   ${suffix}` : ""}`);
	}
	if (!asArray<PageLine>(page.lines).length) lines.push("  (empty page)");

	return truncate(lines.join("\n"));
}

function formatPageList(pages: unknown): string {
	const list = asArray<Record<string, unknown>>(pages);
	if (!list.length) return "no pages";
	// No lastModified here on purpose: OneNote's hierarchy API reports a stale one.
	return list.map((page) => `- ${asString(page.name)}  ${asString(page.id)}  created=${asString(page.created)}`).join("\n");
}

function formatEditChanges(data: Record<string, unknown>): string {
	const changes = asArray<EditChange>(data.changes);
	if (!changes.length) return "no change";
	const out: string[] = [];
	for (const change of changes) {
		out.push(`outline ${change.outlineId}`);
		for (const item of asArray(change.changed)) out.push(`  ~ "${item.before}"  ->  "${item.after}"`);
		for (const item of asArray(change.removed)) out.push(`  - delete "${item.text}"`);
		out.push(`  resulting paragraphs: ${asArray<string>(change.after).map((text) => JSON.stringify(text)).join(", ")}`);
	}
	return out.join("\n");
}

// --- write plumbing ---------------------------------------------------------

async function confirmWrite(ctx: ExtensionContext, summary: string): Promise<boolean> {
	if (!ctx.hasUI) return true;
	return await ctx.ui.confirm("Apply this OneNote change?", summary);
}

interface WritePlan {
	op: string;
	args: Record<string, unknown>;
	/** Asked of the user verbatim on apply. */
	summary: string;
	/** How the plan itself is described before anything is sent. */
	intent: string;
	/**
	 * How a bridge result is turned into text. It is told whether the call was applied, because a
	 * past-tense summary of a dry run reads as if the write already happened.
	 */
	describe: (data: Record<string, unknown>, applied: boolean) => string;
	/** True when the page does not exist yet, so the bridge cannot preview it. */
	skipBridgePreview?: boolean;
}

interface WriteOutcome {
	content: Array<{ type: "text"; text: string }>;
	details: Record<string, unknown>;
	structuredContent: Record<string, unknown>;
}

async function runWrite(ctx: ExtensionContext, signal: AbortSignal | undefined, plan: WritePlan, dryRun: boolean): Promise<WriteOutcome> {
	// A dry run is a real bridge call: it validates the target against the live page and returns
	// the exact change set OneNote would receive, instead of a preview guessed on this side.
	const previewData = plan.skipBridgePreview ? undefined : await callBridge(plan.op, { ...plan.args, apply: false }, signal);
	const previewText = previewData ? plan.describe(previewData, false) : plan.intent;

	if (dryRun) {
		return {
			content: [{ type: "text", text: `Dry run, nothing was written.\n${plan.intent}${previewData ? `\n\n${previewText}` : ""}` }],
			details: { dryRun: true, op: plan.op, preview: previewText, args: plan.args },
			structuredContent: { status: "dry-run", preview: previewText, page: previewData?.page },
		};
	}

	if (!(await confirmWrite(ctx, `${plan.intent}\n\n${previewText}`))) {
		return {
			content: [{ type: "text", text: "The user declined this change; nothing was written." }],
			details: { cancelled: true, op: plan.op },
			structuredContent: { status: "cancelled" },
		};
	}

	const data = await callBridge(plan.op, { ...plan.args, apply: true }, signal);
	return {
		content: [{ type: "text", text: `${plan.describe(data, true)}\n\n${formatPage(data.page as Record<string, unknown>)}` }],
		details: { dryRun: false, op: plan.op, result: data },
		structuredContent: { status: "applied", page: data.page as Record<string, unknown>, changes: data.changes },
	};
}

function describeLines(lines: string[]): string {
	return lines.map((line, index) => `  ${index + 1}. ${line}`).join("\n");
}

function pickTarget(params: Record<string, unknown>): Record<string, unknown> {
	const target: Record<string, unknown> = {};
	for (const key of ["pageId", "notebook", "section", "page"]) {
		if (typeof params[key] === "string" && params[key]) target[key] = params[key];
	}
	return target;
}

function targetLabel(target: Record<string, unknown>): string {
	return asString(target.pageId) || `${asString(target.notebook) || "?"} / ${asString(target.section) || "?"} / ${asString(target.page) || "?"}`;
}

/** OneNote's image format pattern is auto|png|emf|jpg, so jpeg is spelled jpg and anything else gets auto. */
function imageFormatFor(path: string, requested?: string): string {
	if (requested) return requested.toLowerCase() === "jpeg" ? "jpg" : requested.toLowerCase();
	switch (extname(path).toLowerCase()) {
		case ".png":
			return "png";
		case ".jpg":
		case ".jpeg":
			return "jpg";
		case ".emf":
			return "emf";
		default:
			return "auto";
	}
}

// --- extension --------------------------------------------------------------

const TARGET_PARAMS = {
	pageId: Type.Optional(Type.String({ description: "Page ID from onenote_pages or onenote_search. Preferred." })),
	notebook: Type.Optional(Type.String({ description: "Notebook name, used with section and page when pageId is unknown" })),
	section: Type.Optional(Type.String({ description: "Section name" })),
	page: Type.Optional(Type.String({ description: "Page name" })),
};

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "onenote_notebooks",
		label: "OneNote notebooks",
		description: "List the Microsoft OneNote notebooks and sections available in the user's Windows OneNote desktop client.",
		promptSnippet: "List OneNote notebooks and sections",
		parameters: Type.Object({}),
		outputSchema: Type.Object({ notebooks: Type.Array(NotebookSchema) }, { additionalProperties: true }),
		annotations: READ_ONLY,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, _params, signal) {
			const data = await callBridge("notebooks", {}, signal);
			const notebooks = asArray<Record<string, unknown>>(data.notebooks);
			const text = notebooks
				.map((notebook) => {
					const sections = asArray<Record<string, unknown>>(notebook.sections);
					const head = `${asString(notebook.name)}  ${asString(notebook.id)}`;
					const body = sections.map((section) => `  - ${asString(section.name)}  ${asString(section.id)}`).join("\n");
					return body ? `${head}\n${body}` : head;
				})
				.join("\n\n");
			return {
				content: [{ type: "text", text: truncate(text || "no notebooks") }],
				details: { notebooks },
				structuredContent: { notebooks },
			};
		},
	});

	pi.registerTool({
		name: "onenote_pages",
		label: "OneNote pages",
		description:
			"List the pages in one OneNote section. Pass sectionId, or notebook plus section names. Returns names, ids and creation times; for a page's live modification time use onenote_read_page.",
		promptSnippet: "List pages in a OneNote section",
		parameters: Type.Object({
			sectionId: Type.Optional(Type.String({ description: "Section ID from onenote_notebooks" })),
			notebook: Type.Optional(Type.String({ description: "Notebook name" })),
			section: Type.Optional(Type.String({ description: "Section name, required when sectionId is omitted" })),
		}),
		outputSchema: Type.Object(
			{ sectionId: Type.String(), section: Type.String(), pages: Type.Array(PageMetaSchema) },
			{ additionalProperties: true },
		),
		annotations: READ_ONLY,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal) {
			const data = await callBridge("pages", { ...params }, signal);
			const text = `section: ${asString(data.section)}\n${formatPageList(data.pages)}`;
			return { content: [{ type: "text", text: truncate(text) }], details: data, structuredContent: data };
		},
	});

	pi.registerTool({
		name: "onenote_search",
		label: "Search OneNote",
		description:
			"Find OneNote pages by name across every notebook. Matching is a case-insensitive substring match on the page name; page bodies are not searched.",
		promptSnippet: "Find OneNote pages by name",
		parameters: Type.Object({
			query: Type.String({ description: "Substring to look for in page names" }),
			limit: Type.Optional(Type.Number({ description: "Maximum matches to return (default 25)" })),
		}),
		outputSchema: Type.Object(
			{
				total: Type.Number(),
				returned: Type.Number(),
				pages: Type.Array(
					Type.Object(
						{ pageId: Type.String(), page: Type.String(), section: Type.String(), notebook: Type.String() },
						{ additionalProperties: true },
					),
				),
			},
			{ additionalProperties: true },
		),
		annotations: READ_ONLY,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal) {
			const data = await callBridge("search", { query: params.query, limit: params.limit }, signal);
			const pages = asArray<Record<string, unknown>>(data.pages);
			const text = pages.length
				? pages
						.map((hit) => `- ${asString(hit.notebook)} / ${asString(hit.section)} / ${asString(hit.page)}  ${asString(hit.pageId)}`)
						.join("\n")
				: "no pages matched";
			const note = data.total !== data.returned ? `\n(${data.total} matches, showing ${data.returned})` : "";
			return { content: [{ type: "text", text: truncate(text + note) }], details: data, structuredContent: data };
		},
	});

	pi.registerTool({
		name: "onenote_read_page",
		label: "Read OneNote page",
		description:
			"Read one OneNote page: its paragraphs as text, each with the objectID needed to reference it in onenote_edit, plus its outlines, tables and images. The reported lastModified is informational and must not be used as a concurrency check.",
		promptSnippet: "Read a OneNote page as text lines",
		parameters: Type.Object({
			...TARGET_PARAMS,
			includeXml: Type.Optional(
				Type.Boolean({ description: "Also return the raw OneNote XML. Large, and it includes the author's account metadata." }),
			),
		}),
		outputSchema: Type.Object({ page: PageSchema }, { additionalProperties: true }),
		annotations: READ_ONLY,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal) {
			const data = await callBridge("read_page", { ...pickTarget(params), includeXml: params.includeXml === true }, signal);
			const page = data.page as Record<string, unknown>;
			const raw = asString(page.rawXml);
			return {
				content: [{ type: "text", text: formatPage(page) + (raw ? `\n\nraw xml:\n${raw}`.slice(0, MAX_TEXT_CHARS) : "") }],
				details: { page },
				structuredContent: { page },
			};
		},
	});

	pi.registerTool({
		name: "onenote_create_page",
		label: "Create OneNote page",
		description:
			"Create a new page in a OneNote section with a title and optional body paragraphs, each its own paragraph in one outline. A page that does not exist yet cannot be previewed from OneNote, so the dry run reports the plan locally. Dry-run by default: pass dryRun=false to create the page.",
		promptSnippet: "Create a OneNote page (dry-run by default)",
		parameters: Type.Object({
			sectionId: Type.Optional(Type.String({ description: "Section ID from onenote_notebooks" })),
			notebook: Type.Optional(Type.String({ description: "Notebook name" })),
			section: Type.Optional(Type.String({ description: "Section name, required when sectionId is omitted" })),
			title: Type.String({ description: "Page title" }),
			lines: Type.Optional(Type.Array(Type.String({ description: "One paragraph" }), { description: "Body paragraphs, in order" })),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to create the page." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: ADDITIVE,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const lines = asArray<string>(params.lines).filter((line) => typeof line === "string");
			const where = params.sectionId ? `section ${params.sectionId}` : `${params.notebook ?? "?"} / ${params.section ?? "?"}`;
			const intent = [
				`Create page "${params.title}" in ${where}`,
				lines.length ? `with ${lines.length} body paragraph(s):\n${describeLines(lines)}` : "with no body text",
			].join("\n");

			return await runWrite(
				ctx,
				signal,
				{
					op: "create_page",
					args: { sectionId: params.sectionId, notebook: params.notebook, section: params.section, title: params.title, lines },
					summary: `Create a page in OneNote?\n\n${intent}`,
					intent,
					describe: (data, applied) =>
						applied
							? `Created page ${asString((data.page as Record<string, unknown>)?.id)}`
							: "The page does not exist yet, so this is the plan that would be sent.",
					skipBridgePreview: true,
				},
				params.dryRun !== false,
			);
		},
	});

	pi.registerTool({
		name: "onenote_append_lines",
		label: "Append to OneNote page",
		description:
			"Append paragraphs to a page as a new outline at the end. Existing content is not touched. Use this for adding to the end of a page; use onenote_edit to change text inside an existing outline. Dry-run by default: pass dryRun=false to write.",
		promptSnippet: "Append paragraphs to a OneNote page as a new outline (dry-run by default)",
		parameters: Type.Object({
			...TARGET_PARAMS,
			lines: Type.Array(Type.String({ description: "One paragraph" }), { description: "Paragraphs to append, in order" }),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to append." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: ADDITIVE,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const lines = asArray<string>(params.lines).filter((line) => typeof line === "string");
			if (!lines.length) throw new Error("onenote_append_lines needs at least one line");
			const target = pickTarget(params);
			const intent = `Append ${lines.length} paragraph(s) to ${targetLabel(target)} as a new outline:\n${describeLines(lines)}`;

			return await runWrite(
				ctx,
				signal,
				{
					op: "append",
					args: { ...target, lines },
					summary: `Append to a OneNote page?\n\n${intent}`,
					intent,
					describe: (data, applied) => {
						const page = data.page as Record<string, unknown>;
						const paragraphs = asArray(page?.lines).length;
						const outlines = asArray(page?.outlines).length;
						return applied
							? `Appended. The page now has ${paragraphs} paragraph(s) across ${outlines} outline(s).`
							: `Would add one outline with ${lines.length} paragraph(s). The page currently has ${paragraphs} paragraph(s) across ${outlines} outline(s).`;
					},
				},
				params.dryRun !== false,
			);
		},
	});

	pi.registerTool({
		name: "onenote_insert_table",
		label: "Insert OneNote table",
		description:
			"Insert a table into a page: give headers and rows as arrays of cell text. Without outline it becomes a new outline at the end of the page; with outline it is appended inside that existing outline. Cells are single paragraphs and cannot contain nested tables. Dry-run by default: pass dryRun=false to write.",
		promptSnippet: "Insert a table into a OneNote page (dry-run by default)",
		parameters: Type.Object({
			...TARGET_PARAMS,
			headers: Type.Optional(Type.Array(Type.String({ description: "One header cell" }), { description: "Optional header row" })),
			rows: Type.Array(Type.Array(Type.String({ description: "One cell" })), { description: "Rows of cell text" }),
			bordersVisible: Type.Optional(Type.Boolean({ description: "Draw cell borders; OneNote's default is false" })),
			hasHeaderRow: Type.Optional(Type.Boolean({ description: "Render the first row as a header row" })),
			columnWidths: Type.Optional(Type.Array(Type.Number({ description: "Width of one column" }), { description: "Optional per-column widths" })),
			outline: Type.Optional(Type.String({ description: "objectID of an existing outline to append the table to" })),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to insert." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: ADDITIVE,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const headers = asArray<string>(params.headers).filter((value) => typeof value === "string");
			const rows = asArray<unknown>(params.rows).map((row) => asArray<string>(row).map((cell) => (typeof cell === "string" ? cell : String(cell ?? ""))));
			if (!rows.length && !headers.length) throw new Error("onenote_insert_table needs headers or rows");
			const target = pickTarget(params);
			const columnCount = Math.max(headers.length, ...rows.map((row) => row.length));
			const intent = [
				`Insert a ${(headers.length ? 1 : 0) + rows.length}x${columnCount} table into ${targetLabel(target)}`,
				params.outline ? `inside outline ${params.outline}` : "as a new outline at the end of the page",
				headers.length ? `header: ${headers.join(" | ")}` : "",
				...rows.map((row) => `row: ${row.join(" | ")}`),
			]
				.filter(Boolean)
				.join("\n");

			return await runWrite(
				ctx,
				signal,
				{
					op: "insert_table",
					args: {
						...target,
						headers,
						rows,
						bordersVisible: params.bordersVisible === true,
						hasHeaderRow: params.hasHeaderRow === true,
						columnWidths: params.columnWidths,
						outline: params.outline,
					},
					summary: `Insert a table into OneNote?\n\n${intent}`,
					intent,
					describe: (data, applied) => {
						const tables = asArray((data.page as Record<string, unknown>)?.tables).length;
						return applied
							? `Inserted the table. The page now has ${tables} table(s).`
							: `Would insert a ${(headers.length ? 1 : 0) + rows.length}x${columnCount} table. The page currently has ${tables} table(s).`;
					},
				},
				params.dryRun !== false,
			);
		},
	});

	pi.registerTool({
		name: "onenote_insert_image",
		label: "Insert OneNote image",
		description:
			"Insert an image file into a page, read from a path this process can reach (a WSL path, or /mnt/c/... for a file on the Windows side). Without outline it becomes a new outline at the end of the page; with outline it is appended inside that existing outline. Without width and height OneNote picks the size. Dry-run by default: pass dryRun=false to write.",
		promptSnippet: "Insert an image file into a OneNote page (dry-run by default)",
		parameters: Type.Object({
			...TARGET_PARAMS,
			path: Type.String({ description: "Image file path readable from this process" }),
			format: Type.Optional(Type.String({ description: "png, jpg, emf or auto; derived from the extension when omitted" })),
			width: Type.Optional(Type.Number({ description: "Rendered width; needs height too" })),
			height: Type.Optional(Type.Number({ description: "Rendered height; needs width too" })),
			alt: Type.Optional(Type.String({ description: "Alternative text stored on the image" })),
			outline: Type.Optional(Type.String({ description: "objectID of an existing outline to append the image to" })),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to insert." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: ADDITIVE,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const size = statSync(params.path).size;
			if (size > MAX_IMAGE_BYTES) {
				throw new Error(`${params.path} is ${size} bytes, above the ${MAX_IMAGE_BYTES}-byte limit this tool imposes`);
			}
			const format = imageFormatFor(params.path, params.format);
			const target = pickTarget(params);
			const intent = [
				`Insert ${params.path} (${(size / 1024).toFixed(0)} KB, format ${format}) into ${targetLabel(target)}`,
				params.outline ? `inside outline ${params.outline}` : "as a new outline at the end of the page",
				params.width && params.height ? `rendered at ${params.width}x${params.height}` : "at OneNote's chosen size",
			].join("\n");

			return await runWrite(
				ctx,
				signal,
				{
					op: "insert_image",
					args: {
						...target,
						base64: readFileSync(params.path).toString("base64"),
						format,
						width: params.width,
						height: params.height,
						alt: params.alt,
						outline: params.outline,
					},
					summary: `Insert an image into OneNote?\n\n${intent}`,
					intent,
					describe: (data, applied) => {
						const images = asArray<Record<string, unknown>>((data.page as Record<string, unknown>)?.images);
						const embedded = images.filter((image) => image.embedded === true).length;
						return applied
							? `Inserted the image. OneNote reports ${images.length} image(s), ${embedded} with embedded bits.`
							: `Would insert one image. The page currently has ${images.length} image(s), ${embedded} with embedded bits.`;
					},
				},
				params.dryRun !== false,
			);
		},
	});

	pi.registerTool({
		name: "onenote_edit",
		label: "Edit OneNote page text",
		description:
			"Change paragraphs inside existing outlines of a page: replace their text with set, delete them with remove, or add paragraphs to an outline with append. Paragraph objectIDs come from onenote_read_page, and outline objectIDs may be used as an append target. OneNote replaces an outline with exactly what the caller sends, so this tool resends each affected outline in full, echoing back OneNote's own XML for everything it is not changing - that is why paragraph XML must never be hand-built. Dry-run by default: the dry run is a real bridge call reporting the exact change set. Pass dryRun=false to apply.",
		promptSnippet: "Edit or delete paragraphs inside an existing OneNote outline (dry-run by default)",
		parameters: Type.Object({
			...TARGET_PARAMS,
			set: Type.Optional(
				Type.Array(
					Type.Object(
						{
							objectID: Type.String({ description: "objectID of the paragraph to replace" }),
							text: Type.String({ description: "New text for that paragraph" }),
						},
						{ additionalProperties: true },
					),
					{ description: "Paragraphs whose text is replaced" },
				),
			),
			remove: Type.Optional(Type.Array(Type.String({ description: "objectID of a paragraph to delete" }), { description: "Paragraphs to delete" })),
			append: Type.Optional(
				Type.Array(
					Type.Object(
						{
							objectID: Type.String({ description: "objectID of the outline (or of any paragraph in it) to add to" }),
							lines: Type.Array(Type.String({ description: "One paragraph" }), { description: "Paragraphs to add at the end of that outline" }),
						},
						{ additionalProperties: true },
					),
					{ description: "Paragraphs to add inside an existing outline" },
				),
			),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to apply." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: REWRITING,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const set = asArray<Record<string, unknown>>(params.set).filter((item) => typeof item?.objectID === "string");
			const remove = asArray<string>(params.remove).filter((value) => typeof value === "string");
			const append = asArray<Record<string, unknown>>(params.append).filter((item) => typeof item?.objectID === "string");
			if (!set.length && !remove.length && !append.length) {
				throw new Error("onenote_edit needs at least one of set, remove or append");
			}
			const target = pickTarget(params);
			const intent = [
				`Edit ${targetLabel(target)}:`,
				...set.map((item) => `  replace ${asString(item.objectID)} with ${JSON.stringify(item.text)}`),
				...remove.map((objectID) => `  delete ${objectID}`),
				...append.map((item) => `  add ${asArray<string>(item.lines).length} paragraph(s) to ${asString(item.objectID)}`),
			].join("\n");

			return await runWrite(
				ctx,
				signal,
				{
					op: "edit",
					args: { ...target, set, remove, append },
					summary: `Apply this edit to OneNote?\n\n${intent}`,
					intent,
					describe: (data, applied) =>
						`${applied ? "Changed" : "Would change"}: ${formatEditChanges(data)}\n\n${applied ? "OneNote now reports" : "The page currently has"} ${asArray((data.page as Record<string, unknown>)?.lines).length} paragraph(s).`,
				},
				params.dryRun !== false,
			);
		},
	});

	pi.registerTool({
		name: "onenote_delete_page",
		label: "Delete OneNote page",
		description:
			"Delete a OneNote page. It goes to the notebook's recycle bin, so it can be restored from OneNote. expectName is required and must match the page the target resolves to, so a stale or wrong id cannot delete a different page. Dry-run by default: pass dryRun=false to delete.",
		promptSnippet: "Delete a OneNote page (dry-run by default)",
		parameters: Type.Object({
			...TARGET_PARAMS,
			expectName: Type.String({ description: "Exact page name the target must have; required safety check" }),
			dryRun: Type.Optional(Type.Boolean({ description: "Default true. Pass false to delete." })),
		}),
		outputSchema: WriteResultSchema,
		annotations: REWRITING,
		exposure: CODEMODE,
		namespace: NAMESPACE,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const target = pickTarget(params);
			const intent = `Delete OneNote page ${targetLabel(target)}, which must be named "${params.expectName}". It goes to the recycle bin.`;

			// Deleting cannot be previewed by asking the bridge for a dry run, because the delete op
			// has nothing to return for a page that is about to stop existing.
			const dryRun = params.dryRun !== false;
			if (dryRun) {
				return {
					content: [{ type: "text", text: `Dry run, nothing was deleted.\n${intent}` }],
					details: { dryRun: true, op: "delete_page", args: { ...target, expectName: params.expectName } },
					structuredContent: { status: "dry-run", preview: intent },
				};
			}
			if (!(await confirmWrite(ctx, `Delete a OneNote page?\n\n${intent}`))) {
				return {
					content: [{ type: "text", text: "The user declined this change; nothing was deleted." }],
					details: { cancelled: true, op: "delete_page" },
					structuredContent: { status: "cancelled" },
				};
			}

			const data = await callBridge("delete_page", { ...target, expectName: params.expectName }, signal);
			return {
				content: [{ type: "text", text: `Deleted page "${asString(data.name)}" (${asString(data.pageId)}). It is in the notebook recycle bin.` }],
				details: { dryRun: false, op: "delete_page", result: data },
				structuredContent: { status: "applied" },
			};
		},
	});
}
