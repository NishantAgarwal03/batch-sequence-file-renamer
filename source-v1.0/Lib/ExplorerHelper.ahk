#Requires AutoHotkey v2.0+

/**
 * ============================================================================
 * ExplorerHelper.ahk - Windows Shell & Desktop Selection Extractor
 * ============================================================================
 * Part of SequenceRenamer v2 Production Suite
 * Purpose: Robust extraction of selected files/folders from Windows Explorer,
 *          Desktop, or clipboard with natural comparison sorting capabilities.
 * ============================================================================
 */
class ExplorerHelper {
    /**
     * Retrieves an Array of full paths of currently selected items in Explorer or Desktop.
     * @returns {Array} Array of string filepaths
     */
    static GetSelectedItems() {
        selected := []

        try {
            hwnd := WinActive("A")
            if !hwnd
                return selected

            className := WinGetClass("ahk_id " . hwnd)

            ; 1. Active File Explorer Window
            if (className == "CabinetWClass" || className == "ExploreWClass") {
                shellApp := ComObject("Shell.Application")
                for window in shellApp.Windows {
                    try {
                        if (window.HWND == hwnd) {
                            items := window.Document.SelectedItems()
                            for item in items {
                                selected.Push(item.Path)
                            }
                            break
                        }
                    } catch {
                        continue
                    }
                }
            }
            ; 2. Desktop Selection (Progman / WorkerW)
            else if (className == "Progman" || className == "WorkerW") {
                selected := ExplorerHelper.GetDesktopSelection()
            }
        } catch as err {
            Logger.Warn("Failed to query Explorer Shell COM: " . err.Message, "ExplorerHelper")
        }

        ; Fallback: If COM returned nothing and clipboard contains files, try clipboard
        if (selected.Length == 0) {
            selected := ExplorerHelper.GetClipboardFiles()
        }

        Logger.Info("Captured " . selected.Length . " selected items from Explorer/Desktop.", "ExplorerHelper")
        return selected
    }

    /**
     * Query desktop selected items via Shell COM desktop folder
     */
    static GetDesktopSelection() {
        selected := []
        try {
            shellApp := ComObject("Shell.Application")
            for window in shellApp.Windows {
                try {
                    if (window.LocationName == "" || window.LocationName == "Desktop") {
                        items := window.Document.SelectedItems()
                        for item in items {
                            selected.Push(item.Path)
                        }
                        if (selected.Length > 0)
                            break
                    }
                } catch {
                    continue
                }
            }
        } catch as err {
            Logger.Debug("Desktop Shell query error: " . err.Message, "ExplorerHelper")
        }
        return selected
    }

    /**
     * Fallback to clipboard if files are copied
     */
    static GetClipboardFiles() {
        files := []
        try {
            clip := A_Clipboard
            Loop Parse, clip, "`n", "`r" {
                line := Trim(A_LoopField)
                if (line != "" && (FileExist(line) || DirExist(line))) {
                    files.Push(line)
                }
            }
        } catch {
            ; Ignore
        }
        return files
    }

    /**
     * Natural Sort comparison for filenames
     */
    static NaturalCompare(a, b) {
        ; Win32 StrCmpLogicalW performs natural numerical string sorting
        return DllCall("Shlwapi.dll\StrCmpLogicalW", "WStr", a, "WStr", b, "Int")
    }
}