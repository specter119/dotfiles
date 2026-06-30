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
      // session.status carries the real state machine:
      //   idle  -> plain turn end, user can keep chatting
      //   busy  -> agent working
      //   retry -> blocked; with `action` it needs the user to resolve
      //            (e.g. update a plan/link); without `action` it auto-retries
      // Only retry-with-action qualifies as "needs User response".
      if (event.type !== "session.status") return;
      const status = (event.properties as any).status;
      if (!status || status.type !== "retry" || !status.action) return;

      const sessionID = (event.properties as any).sessionID;
      let title = "OpenCode";
      const message = status.action.message || status.message || "Session needs your input";

      try {
        const session = await client.session.get({ path: { id: sessionID } });
        if (session.data?.title) {
          title = `OpenCode: ${session.data.title}`;
        }
      } catch {
        // Fallback to defaults
      }

      sendNotification(message, title);
    },
  };
};

export default notificationPlugin;
