import type { Plugin } from "@opencode-ai/plugin";

const formatterPlugin: Plugin = async ({ $ }) => {
  return {
    "tool.execute.after": async (ctx, output) => {
      if (!["edit", "write"].includes(ctx.tool)) return;

      const filePath = output.metadata?.filePath || output.metadata?.path;
      if (!filePath) return;

      try {
        // Python → ruff
        if (filePath.match(/\.py$/)) {
          await $`ruff format ${filePath}`.quiet();
        }
        // JS/TS/JSON/CSS → biome (fast Rust-based formatter)
        else if (filePath.match(/\.(ts|tsx|js|jsx|json|css)$/)) {
          await $`bunx @biomejs/biome format --write ${filePath}`.quiet();
        }
        // Markup/Config → prettier (biome lacks md/yaml/scss/html support)
        else if (filePath.match(/\.(md|yaml|yml|scss|html)$/)) {
          await $`bunx prettier --write ${filePath}`.quiet();
        }
        // Rust → rustfmt
        else if (filePath.match(/\.rs$/)) {
          await $`rustfmt ${filePath}`.quiet();
        }
        // Go → gofmt
        else if (filePath.match(/\.go$/)) {
          await $`gofmt -w ${filePath}`.quiet();
        }
      } catch {
        // formatter not found or failed, skip silently
      }
    },
  };
};

export default formatterPlugin;
