import type { Plugin } from "@opencode-ai/plugin";

// Base URLs of providers that support Anthropic-style prompt caching.
const PROVIDER_BASE_URLS = ["{{agent.enterprise_llm_base_url}}"];

let orig: typeof globalThis.fetch | undefined;

function isRecord(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function applyMarkerToMessage(
  msg: Record<string, unknown>,
): Record<string, unknown> {
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
    };
  }

  if (Array.isArray(msg.content) && msg.content.length > 0) {
    const content = [...msg.content];
    const lastBlock = content[content.length - 1];
    if (isRecord(lastBlock) && !lastBlock.cache_control) {
      content[content.length - 1] = {
        ...lastBlock,
        cache_control: { type: "ephemeral" },
      };
    }
    return { ...msg, content };
  }

  return msg;
}

function addCacheMarkers(body: unknown): unknown {
  if (
    !isRecord(body) ||
    !Array.isArray(body.messages) ||
    body.messages.length === 0
  )
    return body;

  const messages = [...body.messages];
  let modified = false;

  if (isRecord(messages[0])) {
    messages[0] = applyMarkerToMessage(messages[0]);
    modified = true;
  }

  const lastIndex = messages.length - 1;
  if (lastIndex > 0 && isRecord(messages[lastIndex])) {
    messages[lastIndex] = applyMarkerToMessage(messages[lastIndex]);
    modified = true;
  }

  if (!modified) return body;
  return { ...body, messages };
}

function matchesProvider(
  input: Parameters<typeof globalThis.fetch>[0],
): boolean {
  try {
    const raw = input instanceof Request ? input.url : String(input);
    return PROVIDER_BASE_URLS.some((base) => base && raw.startsWith(base));
  } catch {
    return false;
  }
}

async function patchedFetch(
  input: Parameters<typeof globalThis.fetch>[0],
  init?: Parameters<typeof globalThis.fetch>[1],
): Promise<Response> {
  const opts = init ? { ...init } : {};

  if (!matchesProvider(input)) {
    return orig!(input, opts);
  }

  if (typeof opts.body === "string") {
    try {
      const parsed = JSON.parse(opts.body);
      const transformed = addCacheMarkers(parsed);
      if (transformed !== parsed) {
        opts.body = JSON.stringify(transformed);
      }
    } catch {
      // not JSON — leave body unchanged
    }
  }

  return orig!(input, opts);
}

const cacheControlPlugin: Plugin = async () => {
  if (!orig) {
    orig = globalThis.fetch.bind(globalThis);
    globalThis.fetch = patchedFetch as typeof globalThis.fetch;
  }
  return {};
};

export default cacheControlPlugin;
