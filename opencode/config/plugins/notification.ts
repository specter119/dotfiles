import type { Plugin } from "@opencode-ai/plugin";
import { execSync, spawn } from "child_process";
import { platform } from "os";

interface NotificationConfig {
  title: string;
  icon: string;
  timeout: number;
  clickAction?: string;
}

function detectEnvironment(): "wsl" | "linux" | "macos" | "windows" | "unknown" {
  const plat = platform();

  if (plat === "win32") return "windows";
  if (plat === "darwin") return "macos";

  if (plat === "linux") {
    try {
      const version = execSync("cat /proc/version", { encoding: "utf-8" });
      if (version.toLowerCase().includes("microsoft") || version.toLowerCase().includes("wsl")) {
        return "wsl";
      }
    } catch {
      // Ignore errors
    }

    if (process.env.DISPLAY || process.env.WAYLAND_DISPLAY) {
      return "linux";
    }
  }

  return "unknown";
}

function sendWslNotification(message: string, config: NotificationConfig): void {
  try {
    const psCmd = `
      Add-Type -AssemblyName System.Windows.Forms;
      $notification = New-Object System.Windows.Forms.NotifyIcon;
      $notification.Icon = [System.Drawing.SystemIcons]::Information;
      $notification.BalloonTipTitle = '${config.title}';
      $notification.BalloonTipText = '${message.replace(/'/g, "''")}';
      $notification.Visible = $true;
      ${config.clickAction ? `
      $notification.Add_BalloonTipClicked({
        Start-Process powershell -ArgumentList '-Command', '${config.clickAction.replace(/'/g, "''")}' -WindowStyle Hidden
      });
      ` : ""}
      $notification.ShowBalloonTip(${config.timeout});
      Start-Sleep -Seconds 1;
      $notification.Dispose();
    `;

    spawn("powershell.exe", ["-Command", psCmd], { detached: true, stdio: "ignore" });
  } catch (error) {
    console.error("Failed to send WSL notification:", error);
  }
}

function sendLinuxNotification(message: string, config: NotificationConfig): void {
  try {
    execSync("which notify-send", { stdio: "ignore" });

    const args = [
      "--app-name", config.title,
      "--icon", config.icon,
      "--expire-time", config.timeout.toString(),
    ];

    if (config.clickAction) {
      args.push("--action", `click=Click to execute: ${config.clickAction}`);
    }

    args.push(config.title, message);

    spawn("notify-send", args, { detached: true, stdio: "ignore" });
  } catch (error) {
    console.error("Failed to send Linux notification:", error);
  }
}

function sendMacosNotification(message: string, config: NotificationConfig): void {
  try {
    const script = `
      display notification "${message.replace(/"/g, '\\"')}" with title "${config.title}" sound name "Glass"
    `;

    spawn("osascript", ["-e", script], { detached: true, stdio: "ignore" });
  } catch (error) {
    console.error("Failed to send macOS notification:", error);
  }
}

function sendWindowsNotification(message: string, config: NotificationConfig): void {
  try {
    const psCmd = `
      Add-Type -AssemblyName System.Windows.Forms;
      $notification = New-Object System.Windows.Forms.NotifyIcon;
      $notification.Icon = [System.Drawing.SystemIcons]::Information;
      $notification.BalloonTipTitle = '${config.title}';
      $notification.BalloonTipText = '${message.replace(/'/g, "''")}';
      $notification.Visible = $true;
      ${config.clickAction ? `
      $notification.Add_BalloonTipClicked({
        Start-Process powershell -ArgumentList '-Command', '${config.clickAction.replace(/'/g, "''")}' -WindowStyle Hidden
      });
      ` : ""}
      $notification.ShowBalloonTip(${config.timeout});
      Start-Sleep -Seconds 1;
      $notification.Dispose();
    `;

    spawn("powershell", ["-Command", psCmd], { detached: true, stdio: "ignore" });
  } catch (error) {
    console.error("Failed to send Windows notification:", error);
  }
}

function sendNotification(message: string, clickAction?: string): void {
  const env = detectEnvironment();
  const config: NotificationConfig = {
    title: "OpenCode",
    icon: "dialog-information",
    timeout: 5000,
    clickAction: clickAction || process.env.CLICK_ACTION,
  };

  switch (env) {
    case "wsl":
      sendWslNotification(message, config);
      break;
    case "linux":
      sendLinuxNotification(message, config);
      break;
    case "macos":
      sendMacosNotification(message, config);
      break;
    case "windows":
      sendWindowsNotification(message, config);
      break;
    default:
      console.error("Unsupported environment for notifications");
  }
}

const notificationPlugin: Plugin = async ({ $ }) => {
  const defaultMessage = process.env.NOTIFICATION_MESSAGE || "Waiting for user input";
  const clickAction = process.env.CLICK_ACTION;

  return {
    "tool.before": async (ctx) => {
      if (ctx.tool === "question" || ctx.tool === "tool.question") {
        sendNotification(defaultMessage, clickAction);
      }
    },

    "tool.execute.after": async (ctx, output) => {
      // No-op: avoid notification spam
    },
  };
};

export default notificationPlugin;
