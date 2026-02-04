import type { Plugin } from "@opencode-ai/plugin";
import { spawn } from "child_process";

function sendNotification(message: string, title = "OpenCode"): void {
  const isWSL = !!process.env.WSL_DISTRO_NAME;

  if (isWSL) {
    const psCmd = `
      Add-Type -AssemblyName System.Windows.Forms;
      $notification = New-Object System.Windows.Forms.NotifyIcon;
      $notification.Icon = [System.Drawing.SystemIcons]::Information;
      $notification.BalloonTipTitle = '${title.replace(/'/g, "''")}';
      $notification.BalloonTipText = '${message.replace(/'/g, "''")}';
      $notification.Visible = $true;
      $notification.ShowBalloonTip(10000);
      Start-Sleep -Seconds 1;
      $notification.Dispose();
    `;
    spawn("powershell.exe", ["-Command", psCmd], { detached: true, stdio: "ignore" });
  } else if (process.platform === "darwin") {
    spawn("osascript", ["-e", `display notification "${message.replace(/"/g, '\\"')}" with title "${title.replace(/"/g, '\\"')}"`], { detached: true, stdio: "ignore" });
  } else if (process.platform === "linux") {
    spawn("notify-send", ["--app-name", title, title, message], { detached: true, stdio: "ignore" });
  }
}

const notificationPlugin: Plugin = async ({ client }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const sessionID = event.properties.sessionID;
        let title = "OpenCode";
        let message = "Waiting for user input";

        try {
          const session = await client.session.get({ path: { id: sessionID } });
          if (session.data?.title) {
            title = `OpenCode: ${session.data.title}`;
          }

          const messagesResp = await client.session.messages({ path: { id: sessionID } });
          const messages = messagesResp.data || [];
          const lastAssistantMsg = messages.filter(m => m.info.role === "assistant").pop();
          if (lastAssistantMsg) {
            const textParts = lastAssistantMsg.parts.filter((p: any) => p.type === "text");
            if (textParts.length > 0) {
              const lastText = (textParts[textParts.length - 1] as any).text || "";
              message = lastText.slice(0, 100) + (lastText.length > 100 ? "..." : "");
            }
          }
        } catch {
          // Fallback to defaults
        }

        sendNotification(message, title);
      }
    },
  };
};

export default notificationPlugin;
