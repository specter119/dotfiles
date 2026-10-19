#Requires AutoHotkey v2.0
#SingleInstance Force

; Hold a key to dictate through the voxtype daemon running in WSL; releasing it
; transcribes and pastes the text into the focused Windows window. Pressing any
; other key while holding discards the recording and lets the combo through.
;
; Talks to voxtype-wsl-bridge.socket in WSL; WSL2 forwards loopback listeners to Windows.

HoldKey := "{{voxtype-wsl-bridge.hold_key}}"
BridgePort := {{voxtype-wsl-bridge.port}}
; Taps shorter than this are treated as accidental and discarded.
MinHoldMs := 250
ClipTimeoutSec := 10
; Terminals bind paste to Ctrl+Shift+V and pass a plain Ctrl+V to the program inside.
TerminalExes := Map("WindowsTerminal.exe", 1, "wezterm-gui.exe", 1, "alacritty.exe", 1, "rio.exe", 1, "kitty.exe", 1)

busy := false
LogFile := A_Temp "\voxtype-wsl-bridge.log"

; Only failures are logged; a silent failure is otherwise invisible from a hotkey.
Trace(msg) {
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", LogFile)
}

DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", Buffer(A_PtrSize = 8 ? 408 : 400))

; Sends one command line to the control socket and returns the reply ("" on failure).
Vox(cmd) {
    reply := ""
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if sock = -1 {
        Trace("socket() failed")
        return reply
    }
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("ws2_32\htons", "UShort", BridgePort, "UShort"), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)
    ; 5s receive timeout so a stuck handler cannot freeze the key handler forever.
    DllCall("ws2_32\setsockopt", "Ptr", sock, "Int", 0xFFFF, "Int", 0x1006, "Int*", 5000, "Int", 4)
    if DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr, "Int", 16) != 0 {
        Trace("connect to 127.0.0.1:" BridgePort " failed for '" cmd "'")
    } else {
        msg := Buffer(StrPut(cmd "`n", "UTF-8") - 1)
        StrPut(cmd "`n", msg, "UTF-8")
        DllCall("ws2_32\send", "Ptr", sock, "Ptr", msg, "Int", msg.Size, "Int", 0)
        rbuf := Buffer(64)
        while (n := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", rbuf, "Int", 64, "Int", 0)) > 0
            reply .= StrGet(rbuf, n, "UTF-8")
    }
    DllCall("ws2_32\closesocket", "Ptr", sock)
    return Trim(reply, " `r`n")
}

NoteComboKey(state, ih, vk, sc) {
    ; The hold key's own auto-repeat must not count as a combo.
    if vk != GetKeyVK(HoldKey)
        state.combo := true
}

OnHold(*) {
    global busy
    if busy
        return
    busy := true
    try {
        ; Masks the hold key so releasing a modifier never focuses a menu bar.
        Send("{Blind}{vkE8}")

        state := {combo: false}
        ih := InputHook("V I")
        ih.KeyOpt("{All}", "N")
        ih.OnKeyDown := NoteComboKey.Bind(state)
        ih.Start()

        pressedAt := A_TickCount
        Vox("start")
        KeyWait(HoldKey)
        ih.Stop()

        if state.combo || A_TickCount - pressedAt < MinHoldMs {
            Vox("cancel")
            return
        }

        saved := ClipboardAll()
        A_Clipboard := ""
        Vox("stop")
        if ClipWait(ClipTimeoutSec) {
            exe := WinGetProcessName("A")
            Send(TerminalExes.Has(exe) ? "^+v" : "^v")
            Sleep(200)
        } else {
            Trace("no transcription reached the clipboard within " ClipTimeoutSec "s")
        }
        A_Clipboard := saved
    } finally {
        busy := false
    }
}

Hotkey("~" HoldKey, OnHold)
