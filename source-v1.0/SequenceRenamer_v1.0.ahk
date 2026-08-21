#Requires AutoHotkey v2.0+
#SingleInstance Force

ProcessSetPriority("High")

#Include "Lib\Logger.ahk"
#Include "Lib\Validator.ahk"
#Include "Lib\ExplorerHelper.ahk"
#Include "Lib\TransactionManager.ahk"
#Include "Lib\RenameEngine.ahk"
#Include "Lib\GuiManager.ahk"

Logger.Init()
TransactionManager.Init()
Logger.Info("SequenceRenamer v1.0 starting up...", "Main")

OnError(GlobalErrorHandler)

A_TrayMenu.Delete()
A_TrayMenu.Add("Open Renamer GUI (Ctrl+Shift+R)", (*) => GuiManager.Show())
A_TrayMenu.Add("Capture Active Explorer Selection", (*) => GuiManager.CaptureExplorerSelection())
A_TrayMenu.Add("Undo Last Batch (Ctrl+Shift+U)", (*) => GuiManager.ExecuteUndo())
A_TrayMenu.Add()
A_TrayMenu.Add("View Logs Folder", (*) => Run(A_ScriptDir . "\Logs"))
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Open Renamer GUI (Ctrl+Shift+R)"

try {
    TrayTip("Press Ctrl+Shift+R in Explorer to rename selected files in order.", "Sequence Renamer v1.0 Active", 1)
}

GuiManager.Show()

^+r::
{
    GuiManager.CaptureExplorerSelection()
}

^+u::
{
    GuiManager.ExecuteUndo()
}

GlobalErrorHandler(err, mode) {
    Logger.Fatal("Unhandled system exception: " . err.Message . " at line " . err.Line . " in " . err.File, "GlobalErrorHandler")
    MsgBox(Format("An unexpected error occurred in Sequence Renamer v1.0:`n`n{1}`n`nFile: {2} (Line {3})", err.Message, err.File, err.Line), "Sequence Renamer v1.0 - Fault", "Icon!")
    return true
}
