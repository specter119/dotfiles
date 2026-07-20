// @ts-nocheck

// Strategy: Place cache_control markers on the system message and the last message.
// - System message: stable prefix, almost always hits cache after the first call.
// - Last message: ensures the full conversation prefix is cached for the next turn.

let orig: typeof globalThis.fetch | undefined

function isRecord(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v)
}

function applyMarkerToMessage(msg: Record<string, unknown>): Record<string, unknown> {
  if (typeof msg.content === "string") {
    return {
      ...msg,
      content: [
        {
          type: "text",
          text: msg.content,
          cache_control: { type: "ephemeral" },
        },
      ],
    }
  }

  if (Array.isArray(msg.content) && msg.content.length > 0) {
    const content = [...msg.content]
    const lastBlock = content[content.length - 1]
    if (isRecord(lastBlock)) {
      content[content.length - 1] = {
        ...lastBlock,
        cache_control: { type: "ephemeral" },
      }
    }
    return { ...msg, content }
  }

  return msg
}

function addCacheMarkers(body: unknown): unknown {
  if (!isRecord(body) || !Array.isArray(body.messages) || body.messages.length === 0) return body

  const messages = [...body.messages]
  let modified = false

  // Mark system message (index 0)
  if (isRecord(messages[0])) {
    messages[0] = applyMarkerToMessage(messages[0])
    modified = true
  }

  // Mark last message (if different from index 0)
  const lastIndex = messages.length - 1
  if (lastIndex > 0 && isRecord(messages[lastIndex])) {
    messages[lastIndex] = applyMarkerToMessage(messages[lastIndex])
    modified = true
  }

  if (!modified) return body
  return { ...body, messages }
}

function isAliCloudProviderRequest(input: Parameters<typeof globalThis.fetch>[0]): boolean {
  try {
    const req = input instanceof Request ? input : new Request(input)
    const pathName = new URL(req.url).pathname
    return pathName.includes("/openai/deployments/ali-copilot")
  } catch {
    return false
  }
}

async function patchedFetch(
  input: Parameters<typeof globalThis.fetch>[0],
  init?: Parameters<typeof globalThis.fetch>[1],
): Promise<Response> {
  const opts = init ? { ...init } : {}

  if (!isAliCloudProviderRequest(input)) {
    return orig(input, opts)
  }

  if (typeof opts.body === "string") {
    try {
      const parsed = JSON.parse(opts.body)
      const transformed = addCacheMarkers(parsed)
      if (transformed !== parsed) {
        opts.body = JSON.stringify(transformed)
      }
    } catch {
      // Not JSON — leave body unchanged.
    }
  }

  return orig(input, opts)
}

const main: (() => Promise<object>) & { id?: unknown; server?: unknown } = async () => {
  if (!orig) {
    orig = globalThis.fetch.bind(globalThis)
    globalThis.fetch = patchedFetch
  }

  return {}
}

const entrypoint = main
entrypoint.id = "opencode-last-message-ephemeral"
entrypoint.server = main

export default entrypoint
