#Requires AutoHotkey v2.0+
#SingleInstance Force
ProcessSetPriority('High')

; ============================================================================
; MODULE: Logger.ahk
; ============================================================================

/**
 * ============================================================================
 * Logger.ahk - Thread-Safe Timestamped Diagnostic Logger
 * ============================================================================
 * Part of SequenceRenamer v2 Production Suite
 * Purpose: Paranoid, fail-safe logging with rotation and level filtering.
 * ============================================================================
 */
class Logger {
    static LogFilePath := A_ScriptDir . "\Logs\Renamer_" . FormatTime(A_Now, "yyyy-MM-dd") . ".log"
    static MaxSizeBytes := 5 * 1024 * 1024 ; 5 MB
    static LogLevel := "INFO" ; DEBUG, INFO, WARN, ERROR, FATAL

    static LevelValues := Map(
        "DEBUG", 1,
        "INFO",  2,
        "WARN",  3,
        "ERROR", 4,
        "FATAL", 5
    )

    static Init() {
        logDir := A_ScriptDir . "\Logs"
        if !DirExist(logDir) {
            try {
                DirCreate(logDir)
            } catch {
                logDir := A_AppData . "\SequenceRenamer\Logs"
                DirCreate(logDir)
                Logger.LogFilePath := logDir . "\Renamer_" . FormatTime(A_Now, "yyyy-MM-dd") . ".log"
            }
        }
        Logger.RotateIfNeeded()
        Logger.Info("Logger initialized. Target: " . Logger.LogFilePath)
    }

    static Debug(msg, context := "") => Logger.Write("DEBUG", msg, context)
    static Info(msg, context := "")  => Logger.Write("INFO",  msg, context)
    static Warn(msg, context := "")  => Logger.Write("WARN",  msg, context)
    static Error(msg, context := "") => Logger.Write("ERROR", msg, context)
    static Fatal(msg, context := "") => Logger.Write("FATAL", msg, context)

    static Write(level, message, context := "") {
        try {
            currentVal := Logger.LevelValues.Has(level) ? Logger.LevelValues[level] : 2
            minVal := Logger.LevelValues.Has(Logger.LogLevel) ? Logger.LevelValues[Logger.LogLevel] : 2

            if (currentVal < minVal)
                return

            timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "." . SubStr(A_MSec . "00", 1, 3)
            ctxStr := context != "" ? " [" . context . "]" : ""
            logEntry := Format("[{1}] [{2:-5}]{3} {4}`r`n", timestamp, level, ctxStr, message)

            fileObj := FileOpen(Logger.LogFilePath, "a", "UTF-8")
            if (fileObj) {
                fileObj.Write(logEntry)
                fileObj.Close()
            }
        } catch as err {
            OutputDebug("Logger Error: " . err.Message)
        }
    }

    static RotateIfNeeded() {
        try {
            if FileExist(Logger.LogFilePath) {
                fileSize := FileGetSize(Logger.LogFilePath)
                if (fileSize > Logger.MaxSizeBytes) {
                    backupPath := StrReplace(Logger.LogFilePath, ".log", "_" . A_Now . ".bak.log")
                    FileMove(Logger.LogFilePath, backupPath, 1)
                }
            }
        } catch {
            ; Suppress rotation errors
        }
    }
}

; ============================================================================
; MODULE: Validator.ahk
; ============================================================================

/**
 * ============================================================================
 * Validator.ahk - Paranoid Input & File System Validator
 * ============================================================================
 * Part of SequenceRenamer v2 Production Suite
 * Purpose: Preempt invalid paths, Windows reserved names, lock conflicts,
 *          and path length limits before any file operation occurs.
 * ============================================================================
 */
class Validator {
    ; Windows invalid filename characters: < > : " / \ | ? *
    static InvalidCharsPattern := '[<>:"/\\|?*\x00-\x1F]'
    
    ; Windows Reserved Device Names
    static ReservedNames := Map(
        "CON", 1, "PRN", 1, "AUX", 1, "NUL", 1,
        "COM1", 1, "COM2", 1, "COM3", 1, "COM4", 1, "COM5", 1, "COM6", 1, "COM7", 1, "COM8", 1, "COM9", 1,
        "LPT1", 1, "LPT2", 1, "LPT3", 1, "LPT4", 1, "LPT5", 1, "LPT6", 1, "LPT7", 1, "LPT8", 1, "LPT9", 1
    )

    static MaxPathLimit := 259

    /**
     * Validates a candidate filename (name + extension, without directory path)
     * @param {String} fileName Candidate filename
     * @returns {Object} { isValid: Boolean, reason: String }
     */
    static ValidateFileName(fileName) {
        if (Trim(fileName) == "") {
            return { isValid: false, reason: "Filename cannot be empty or pure whitespace." }
        }

        ; Check for invalid characters
        if RegExMatch(fileName, Validator.InvalidCharsPattern) {
            return { isValid: false, reason: 'Filename contains illegal Windows characters (< > : " / \ | ? * or control characters).' }
        }

        ; Trailing spaces or dots are invalid in Win32
        if (SubStr(fileName, -1) == " " || SubStr(fileName, -1) == ".") {
            return { isValid: false, reason: "Filename cannot end with a period or space." }
        }

        ; Extract base name without extension for reserved device name check
        SplitPath(fileName, , , , &baseName)
        if Validator.ReservedNames.Has(StrUpper(baseName)) {
            return { isValid: false, reason: "'" . baseName . "' is a reserved Windows system device name." }
        }

        return { isValid: true, reason: "" }
    }

    /**
     * Validates full path length and syntax
     * @param {String} fullPath Absolute file path
     * @returns {Object} { isValid: Boolean, reason: String }
     */
    static ValidateFullPath(fullPath) {
        if (StrLen(fullPath) > Validator.MaxPathLimit) {
            return { isValid: false, reason: "Path exceeds standard Windows MAX_PATH limit (" . StrLen(fullPath) . "/260 chars)." }
        }
        
        SplitPath(fullPath, &fileName, &dir)
        if (dir == "" || !DirExist(dir)) {
            return { isValid: false, reason: "Parent directory does not exist: " . dir }
        }

        return Validator.ValidateFileName(fileName)
    }

    /**
     * Probes if a file is currently locked or open exclusively by another process.
     * Uses Win32 CreateFileW with GENERIC_READ | GENERIC_WRITE.
     * @param {String} filePath Full path to the file
     * @returns {Boolean} True if file is locked or cannot be opened for modification
     */
    static IsFileLocked(filePath) {
        if !FileExist(filePath)
            return false

        if InStr(FileGetAttrib(filePath), "D")
            return false ; Directory

        ; GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
        GENERIC_READ_WRITE := 0xC0000000
        FILE_SHARE_READ := 0x00000001
        OPEN_EXISTING := 3
        FILE_ATTRIBUTE_NORMAL := 0x80
        INVALID_HANDLE_VALUE := -1

        hFile := DllCall("CreateFileW",
            "Str", filePath,
            "UInt", GENERIC_READ_WRITE,
            "UInt", FILE_SHARE_READ,
            "Ptr", 0,
            "UInt", OPEN_EXISTING,
            "UInt", FILE_ATTRIBUTE_NORMAL,
            "Ptr", 0,
            "Ptr")

        if (hFile == INVALID_HANDLE_VALUE) {
            err := DllCall("GetLastError", "UInt")
            Logger.Warn("File lock detected for '" . filePath . "' (Win32 Error: " . err . ")", "Validator")
            return true
        }

        DllCall("CloseHandle", "Ptr", hFile)
        return false
    }

    /**
     * Sanitizes a string into a safe filename
     * @param {String} str Input string
     * @param {String} replacement Replacement character for invalid symbols
     * @returns {String} Safe filename
     */
    static Sanitize(str, replacement := "_") {
        safe := RegExReplace(str, Validator.InvalidCharsPattern, replacement)
        safe := Trim(safe, " .")
        if (safe == "")
            safe := "Unnamed"
        return safe
    }
}

; ============================================================================
; MODULE: ExplorerHelper.ahk
; ============================================================================

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

; ============================================================================
; MODULE: TransactionManager.ahk
; ============================================================================

/**
 * ============================================================================
 * TransactionManager.ahk - Transactional Rollback & Undo Ledger (v1.1)
 * ============================================================================
 * Dual-tier transaction engine:
 * 1. Immediate in-memory session stack for 100% reliable 1-click Undo.
 * 2. Persistent disk-backed TSV ledger for cross-session rollback.
 * ============================================================================
 */
class TransactionManager {
    static LedgerFile := A_ScriptDir . "\Logs\TransactionHistory.tsv"
    static SessionHistory := []
    static CurrentBatch := []

    static Init() {
        logDir := A_ScriptDir . "\Logs"
        if !DirExist(logDir) {
            try {
                DirCreate(logDir)
            } catch {
                logDir := A_AppData . "\SequenceRenamer\Logs"
                DirCreate(logDir)
                TransactionManager.LedgerFile := logDir . "\TransactionHistory.tsv"
            }
        }
    }

    static BeginTransaction() {
        TransactionManager.CurrentBatch := []
        txId := FormatTime(A_Now, "yyyyMMdd_HHmmss") . "_" . Random(1000, 9999)
        Logger.Info("Transaction started: " . txId, "TxManager")
        return txId
    }

    static Record(originalPath, stagedPath, finalPath) {
        TransactionManager.CurrentBatch.Push({
            originalPath: originalPath,
            stagedPath: stagedPath,
            finalPath: finalPath
        })
    }

    static Commit(txId) {
        if (TransactionManager.CurrentBatch.Length == 0) {
            return
        }

        entry := {
            txId: txId,
            timestamp: FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"),
            operations: TransactionManager.CurrentBatch
        }

        ; Save to in-memory session stack
        TransactionManager.SessionHistory.Push(entry)

        ; Append to disk TSV journal
        try {
            fileObj := FileOpen(TransactionManager.LedgerFile, "a", "UTF-8")
            if (fileObj) {
                fileObj.WriteLine("===TX|" . txId . "|" . entry.timestamp . "===")
                for op in TransactionManager.CurrentBatch {
                    fileObj.WriteLine(op.originalPath . "`t" . op.finalPath)
                }
                fileObj.Close()
            }
            Logger.Info("Transaction committed: " . txId . " (" . TransactionManager.CurrentBatch.Length . " ops)", "TxManager")
        } catch as err {
            Logger.Warn("Disk transaction journal write deferred: " . err.Message, "TxManager")
        }
    }

    static UndoLast() {
        operations := []
        txId := ""

        ; Prefer memory session stack
        if (TransactionManager.SessionHistory.Length > 0) {
            lastTx := TransactionManager.SessionHistory.Pop()
            operations := lastTx.operations
            txId := lastTx.txId
        } else {
            ; Fallback to disk ledger
            diskTx := TransactionManager.PopLastDiskTx()
            if (diskTx != "") {
                operations := diskTx.operations
                txId := diskTx.txId
            }
        }

        if (operations.Length == 0) {
            return { success: false, count: 0, errors: ["No previous transactions found to undo."] }
        }

        errors := []
        restoredCount := 0
        stagedUndo := []

        Logger.Info("Starting Undo for Transaction: " . txId . " (" . operations.Length . " files)", "TxManager")

        ; Pass 1: Staging to avoid collision
        idx := operations.Length
        while (idx >= 1) {
            op := operations[idx]
            currentFile := op.finalPath
            targetFile := op.originalPath

            if FileExist(currentFile) || DirExist(currentFile) {
                tempUndo := currentFile . ".undo_tmp_" . A_TickCount . "_" . idx
                try {
                    FileMove(currentFile, tempUndo, 1)
                    stagedUndo.Push({ temp: tempUndo, original: targetFile })
                } catch as err {
                    errors.Push("Failed to stage undo for '" . currentFile . "': " . err.Message)
                }
            } else {
                errors.Push("File not found on disk for undo: '" . currentFile . "'")
            }
            idx--
        }

        ; Pass 2: Final restore pass
        for item in stagedUndo {
            try {
                FileMove(item.temp, item.original, 1)
                restoredCount++
            } catch as err {
                errors.Push("Failed to restore original file '" . item.original . "': " . err.Message)
            }
        }

        Logger.Info("Undo completed. Restored: " . restoredCount . ", Errors: " . errors.Length, "TxManager")
        return { success: (restoredCount > 0 && errors.Length == 0), count: restoredCount, errors: errors }
    }

    static PopLastDiskTx() {
        if !FileExist(TransactionManager.LedgerFile) {
            return ""
        }
        try {
            content := FileRead(TransactionManager.LedgerFile, "UTF-8")
            blocks := StrSplit(content, "===TX|")
            if (blocks.Length <= 1) {
                return ""
            }

            lastBlock := blocks.Pop()
            lines := StrSplit(Trim(lastBlock), "`n", "`r")
            if (lines.Length == 0) {
                return ""
            }

            headerLine := lines[1]
            headerParts := StrSplit(headerLine, "|")
            txId := headerParts[1]

            ops := []
            Loop lines.Length - 1 {
                l := lines[A_Index + 1]
                if (Trim(l) == "" || InStr(l, "===")) {
                    continue
                }
                parts := StrSplit(l, "`t")
                if (parts.Length >= 2) {
                    ops.Push({ originalPath: parts[1], finalPath: parts[2] })
                }
            }

            ; Rewrite file without popped transaction
            newContent := ""
            for i, b in blocks {
                if (i > 1) {
                    newContent .= "===TX|" . b
                }
            }
            fileObj := FileOpen(TransactionManager.LedgerFile, "w", "UTF-8")
            if (fileObj) {
                fileObj.Write(newContent)
                fileObj.Close()
            }

            return { txId: txId, operations: ops }
        } catch {
            return ""
        }
    }
}


; ============================================================================
; MODULE: RenameEngine.ahk
; ============================================================================

class RenameEngine {
    static GeneratePlan(filePaths, options) {
        plan := []
        usedTargetPaths := Map()

        pattern := options.HasOwnProp("pattern") ? options.pattern : "{i}_{name}.{ext}"
        startIndex := options.HasOwnProp("startIndex") ? options.startIndex : 1
        step := options.HasOwnProp("step") ? options.step : 1
        padding := options.HasOwnProp("padding") ? options.padding : 3
        caseMode := options.HasOwnProp("caseMode") ? options.caseMode : "None"

        for idx, originalPath in filePaths {
            SplitPath(originalPath, &oldFileName, &dir, &ext, &nameNoExt)
            isDir := DirExist(originalPath)

            currentIndex := startIndex + ((idx - 1) * step)
            padFormat := "{:0" . padding . "d}"
            formattedIndex := Format(padFormat, currentIndex)

            SplitPath(dir, &parentDirName)

            newName := pattern
            newName := StrReplace(newName, "{i}", formattedIndex)
            newName := StrReplace(newName, "{001}", formattedIndex)
            newName := StrReplace(newName, "{name}", nameNoExt)
            newName := StrReplace(newName, "{parent}", parentDirName)
            newName := StrReplace(newName, "{date}", FormatTime(A_Now, "yyyy-MM-dd"))
            newName := StrReplace(newName, "{time}", FormatTime(A_Now, "HH-mm-ss"))

            if InStr(newName, "{ext}") {
                if (ext != "" && !isDir) {
                    newName := StrReplace(newName, "{ext}", ext)
                } else {
                    newName := StrReplace(newName, ".{ext}", "")
                    newName := StrReplace(newName, "{ext}", "")
                }
            } else if (ext != "" && !isDir && !InStr(newName, "." . ext)) {
                newName .= "." . ext
            }

            if (caseMode == "Upper") {
                newName := StrUpper(newName)
            } else if (caseMode == "Lower") {
                newName := StrLower(newName)
            } else if (caseMode == "Title") {
                newName := StrTitle(newName)
            }

            targetPath := dir . "\" . newName

            val := Validator.ValidateFileName(newName)
            isValid := val.isValid
            errorReason := val.reason

            lowerTarget := StrLower(targetPath)
            if (isValid && usedTargetPaths.Has(lowerTarget)) {
                isValid := false
                errorReason := "Duplicate target name collision."
            } else {
                usedTargetPaths[lowerTarget] := true
            }

            plan.Push({
                index: idx,
                originalPath: originalPath,
                dir: dir,
                oldName: oldFileName,
                newName: newName,
                targetPath: targetPath,
                isDir: isDir,
                isValid: isValid,
                error: errorReason,
                status: isValid ? "Ready" : "Error: " . errorReason
            })
        }

        return plan
    }

    static Execute(plan, progressCallback := "") {
        errors := []
        renamedCount := 0
        total := plan.Length

        if (total == 0) {
            return { success: true, renamedCount: 0, errors: [] }
        }

        for item in plan {
            if !item.isValid {
                errors.Push("Pre-flight aborted: '" . item.oldName . "' -> " . item.error)
                return { success: false, renamedCount: 0, errors: errors }
            }
            if !FileExist(item.originalPath) && !DirExist(item.originalPath) {
                errors.Push("Source item not found: '" . item.originalPath . "'")
                return { success: false, renamedCount: 0, errors: errors }
            }
            if Validator.IsFileLocked(item.originalPath) {
                errors.Push("Source file is locked: '" . item.originalPath . "'")
                return { success: false, renamedCount: 0, errors: errors }
            }
        }

        txId := TransactionManager.BeginTransaction()
        stagedItems := []

        for idx, item in plan {
            if (item.originalPath == item.targetPath) {
                continue
            }

            tempToken := Format(".tmp_seq_{1}_{2}_{3}", txId, idx, Random(1000, 9999))
            tempPath := item.originalPath . tempToken

            try {
                FileMove(item.originalPath, tempPath, 1)
                stagedItems.Push({
                    originalPath: item.originalPath,
                    tempPath: tempPath,
                    targetPath: item.targetPath,
                    oldName: item.oldName,
                    newName: item.newName
                })
            } catch as err {
                errors.Push("Staging failed for '" . item.oldName . "': " . err.Message)
                RenameEngine.RollbackStaging(stagedItems)
                return { success: false, renamedCount: 0, errors: errors }
            }

            if (progressCallback != "") {
                progressCallback.Call(idx, total * 2, "Staging: " . item.oldName)
            }
        }

        committedItems := []
        for idx, item in stagedItems {
            try {
                FileMove(item.tempPath, item.targetPath, 1)
                TransactionManager.Record(item.originalPath, item.tempPath, item.targetPath)
                committedItems.Push(item)
                renamedCount++
            } catch as err {
                errors.Push("Commit failed for '" . item.oldName . "' -> '" . item.newName . "': " . err.Message)
                RenameEngine.RollbackCommitted(committedItems)
                RenameEngine.RollbackStaging(stagedItems, committedItems.Length + 1)
                return { success: false, renamedCount: 0, errors: errors }
            }

            if (progressCallback != "") {
                progressCallback.Call(total + idx, total * 2, "Renamed: " . item.newName)
            }
        }

        TransactionManager.Commit(txId)
        return { success: true, renamedCount: renamedCount, errors: [] }
    }

    static RollbackStaging(stagedItems, startIndex := 1) {
        idx := stagedItems.Length
        while (idx >= startIndex) {
            item := stagedItems[idx]
            try {
                if FileExist(item.tempPath) || DirExist(item.tempPath) {
                    FileMove(item.tempPath, item.originalPath, 1)
                }
            }
            idx--
        }
    }

    static RollbackCommitted(committedItems) {
        idx := committedItems.Length
        while (idx >= 1) {
            item := committedItems[idx]
            try {
                if FileExist(item.targetPath) || DirExist(item.targetPath) {
                    FileMove(item.targetPath, item.originalPath, 1)
                }
            }
            idx--
        }
    }
}


; ============================================================================
; MODULE: GuiManager.ahk
; ============================================================================

class GuiManager {
    static MainGui := ""
    static LV := ""
    static PatternEdit := ""
    static StartIndexEdit := ""
    static StepEdit := ""
    static PaddingEdit := ""
    static CaseDropdown := ""
    static StatusText := ""
    static ProgressBar := ""
    static BtnExecute := ""
    static BtnUndo := ""
    
    static CurrentFiles := []
    static CurrentPlan := []
    static PreviewCallback := ""

    static Create() {
        if (GuiManager.MainGui != "") {
            GuiManager.MainGui.Show()
            return
        }

        g := Gui("+Resize +MinSize750x550", "Sequence Renamer v1.0 (Stable Edition)")
        g.SetFont("s9", "Segoe UI")
        g.BackColor := "F9FBFD"

        g.SetFont("s11 bold", "Segoe UI")
        g.Add("Text", "x15 y12 w550 h25 c004488", "Sequence File & Folder Renamer v1.0")
        g.SetFont("s9 norm", "Segoe UI")
        g.Add("Text", "x15 y35 w700 h18 c666666", "Reorder items left-to-right, configure sequential pattern, and rename with 2-pass transactional safety.")

        g.Add("GroupBox", "x15 y60 w710 h100", "Renaming Template & Sequence Rules")
        
        g.Add("Text", "x30 y85 w60 h20", "Pattern:")
        GuiManager.PatternEdit := g.Add("Edit", "x95 y82 w260 h23", "{i}_{name}.{ext}")
        GuiManager.PatternEdit.OnEvent("Change", (*) => GuiManager.TriggerDebouncedPreview())

        g.Add("Text", "x370 y85 w40 h20", "Start:")
        GuiManager.StartIndexEdit := g.Add("Edit", "x415 y82 w45 h23 Number", "1")
        GuiManager.StartIndexEdit.OnEvent("Change", (*) => GuiManager.TriggerDebouncedPreview())

        g.Add("Text", "x470 y85 w35 h20", "Step:")
        GuiManager.StepEdit := g.Add("Edit", "x510 y82 w45 h23 Number", "1")
        GuiManager.StepEdit.OnEvent("Change", (*) => GuiManager.TriggerDebouncedPreview())

        g.Add("Text", "x565 y85 w50 h20", "Padding:")
        GuiManager.PaddingEdit := g.Add("Edit", "x620 y82 w45 h23 Number", "3")
        GuiManager.PaddingEdit.OnEvent("Change", (*) => GuiManager.TriggerDebouncedPreview())

        g.Add("Text", "x30 y122 w60 h20", "Case:")
        GuiManager.CaseDropdown := g.Add("DropDownList", "x95 y118 w110 Choose1", ["None", "Upper", "Lower", "Title"])
        GuiManager.CaseDropdown.OnEvent("Change", (*) => GuiManager.TriggerDebouncedPreview())

        btnTokens := [
            { text: "+{i}", token: "{i}" },
            { text: "+{name}", token: "{name}" },
            { text: "+{ext}", token: "{ext}" },
            { text: "+{date}", token: "{date}" },
            { text: "+{parent}", token: "{parent}" }
        ]
        tx := 220
        for b in btnTokens {
            btn := g.Add("Button", Format("x{1} y118 w65 h23", tx), b.text)
            tok := b.token
            btn.OnEvent("Click", ((t, *) => GuiManager.InsertToken(t)).Bind(tok))
            tx += 70
        }

        g.SetFont("s9 bold", "Segoe UI")
        g.Add("Text", "x15 y168 w400 h18", "Selected Items Order (Processed Left-to-Right / Top-to-Bottom):")
        g.SetFont("s9 norm", "Segoe UI")
        GuiManager.LV := g.Add("ListView", "x15 y188 w590 h260 Grid -Multi", ["#", "Current Name", "New Name Preview", "Status", "Directory"])
        GuiManager.LV.ModifyCol(1, "40 Center Integer")
        GuiManager.LV.ModifyCol(2, "180")
        GuiManager.LV.ModifyCol(3, "240")
        GuiManager.LV.ModifyCol(4, "70")
        GuiManager.LV.ModifyCol(5, "60")

        rx := 615
        btnUp := g.Add("Button", Format("x{1} y188 w110 h28", rx), "▲ Move Up")
        btnUp.OnEvent("Click", (*) => GuiManager.MoveSelected(-1))

        btnDown := g.Add("Button", Format("x{1} y220 w110 h28", rx), "▼ Move Down")
        btnDown.OnEvent("Click", (*) => GuiManager.MoveSelected(1))

        btnTop := g.Add("Button", Format("x{1} y252 w110 h26", rx), "⤒ Move to Top")
        btnTop.OnEvent("Click", (*) => GuiManager.MoveToExtreme(true))

        btnBottom := g.Add("Button", Format("x{1} y280 w110 h26", rx), "⤓ Move to Bottom")
        btnBottom.OnEvent("Click", (*) => GuiManager.MoveToExtreme(false))

        btnReverse := g.Add("Button", Format("x{1} y315 w110 h26", rx), "⇄ Reverse Order")
        btnReverse.OnEvent("Click", (*) => GuiManager.ReverseList())

        btnSortNat := g.Add("Button", Format("x{1} y345 w110 h26", rx), "🔤 Natural Sort")
        btnSortNat.OnEvent("Click", (*) => GuiManager.SortNatural())

        btnRemove := g.Add("Button", Format("x{1} y385 w110 h26", rx), "✕ Remove Item")
        btnRemove.OnEvent("Click", (*) => GuiManager.RemoveSelected())

        btnClear := g.Add("Button", Format("x{1} y415 w110 h26", rx), "🗑 Clear All")
        btnClear.OnEvent("Click", (*) => GuiManager.ClearAll())

        GuiManager.ProgressBar := g.Add("Progress", "x15 y458 w710 h15 Range0-100 c0077CC", 0)
        GuiManager.StatusText := g.Add("Text", "x15 y480 w480 h20 c444444", "Ready. Select files in Explorer (Ctrl+Shift+R) or drag & drop files here.")

        GuiManager.BtnUndo := g.Add("Button", "x510 y476 w100 h32", "↺ Undo Last")
        GuiManager.BtnUndo.OnEvent("Click", (*) => GuiManager.ExecuteUndo())

        GuiManager.BtnExecute := g.Add("Button", "x618 y476 w105 h32 Default", "▶ Rename Now")
        GuiManager.BtnExecute.OnEvent("Click", (*) => GuiManager.ExecuteBatch())

        g.OnEvent("DropFiles", (guiObj, guiCtrl, fileArray, x, y) => GuiManager.OnDropFiles(fileArray))
        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Size", (guiObj, minMax, width, height) => GuiManager.OnResize(width, height))

        GuiManager.MainGui := g
        GuiManager.UpdateListView()
    }

    static Show() {
        if (GuiManager.MainGui == "") {
            GuiManager.Create()
        }
        GuiManager.MainGui.Show("w740 h520 Center")
    }

    static OnResize(width, height) {
        if (width < 600 || height < 400) {
            return
        }
        try {
            GuiManager.LV.Move(, , width - 150, height - 260)
            GuiManager.ProgressBar.Move(, height - 62, width - 30)
            GuiManager.StatusText.Move(, height - 40, width - 240)
            GuiManager.BtnExecute.Move(width - 115, height - 44)
            GuiManager.BtnUndo.Move(width - 225, height - 44)
        }
    }

    static InsertToken(tok) {
        current := GuiManager.PatternEdit.Value
        GuiManager.PatternEdit.Value := current . tok
        GuiManager.TriggerDebouncedPreview()
    }

    static OnDropFiles(fileArray) {
        if (GuiManager.MainGui == "") {
            GuiManager.Create()
        }
        addedCount := 0
        for filePath in fileArray {
            if (FileExist(filePath) || DirExist(filePath)) {
                exists := false
                for item in GuiManager.CurrentFiles {
                    if (item == filePath) {
                        exists := true
                        break
                    }
                }
                if (!exists) {
                    GuiManager.CurrentFiles.Push(filePath)
                    addedCount++
                }
            }
        }
        GuiManager.StatusText.Value := Format("Added {1} dropped items. Total: {2}", addedCount, GuiManager.CurrentFiles.Length)
        GuiManager.UpdateListView()
    }

    static CaptureExplorerSelection() {
        if (GuiManager.MainGui == "") {
            GuiManager.Create()
        }
        items := ExplorerHelper.GetSelectedItems()
        if (items.Length == 0) {
            MsgBox("No files or folders are currently selected in active Windows Explorer or Desktop.`n`nTip: Select files in Explorer and press Ctrl+Shift+R, or drag & drop files directly into this window.", "Sequence Renamer v1.0", "Iconi")
            GuiManager.Show()
            return
        }
        GuiManager.CurrentFiles := items
        GuiManager.StatusText.Value := Format("Captured {1} items from active Explorer.", items.Length)
        GuiManager.UpdateListView()
        GuiManager.Show()
    }

    static TriggerDebouncedPreview() {
        if (GuiManager.MainGui == "") {
            return
        }
        if (!GuiManager.PreviewCallback) {
            GuiManager.PreviewCallback := () => GuiManager.UpdateListView()
        }
        SetTimer(GuiManager.PreviewCallback, -120)
    }

    static UpdateListView() {
        GuiManager.LV.Opt("-Redraw")
        GuiManager.LV.Delete()

        if (GuiManager.CurrentFiles.Length == 0) {
            GuiManager.LV.Add("", "-", "📂 (No files selected yet)", "-", "Waiting", "-")
            GuiManager.LV.Opt("+Redraw")
            GuiManager.StatusText.Value := "📂 Queue is empty. Select files in Explorer and press Ctrl+Shift+R, or drag & drop files here."
            GuiManager.BtnExecute.Enabled := false
            return
        }

        options := {
            pattern: GuiManager.PatternEdit.Value,
            startIndex: Integer(GuiManager.StartIndexEdit.Value || 1),
            step: Integer(GuiManager.StepEdit.Value || 1),
            padding: Integer(GuiManager.PaddingEdit.Value || 1),
            caseMode: GuiManager.CaseDropdown.Text
        }

        GuiManager.CurrentPlan := RenameEngine.GeneratePlan(GuiManager.CurrentFiles, options)

        hasErrors := false
        for item in GuiManager.CurrentPlan {
            GuiManager.LV.Add("", item.index, item.oldName, item.newName, item.status, item.dir)
            if (!item.isValid) {
                hasErrors := true
            }
        }

        GuiManager.LV.Opt("+Redraw")
        
        if (hasErrors) {
            GuiManager.StatusText.Value := "⚠️ Errors or collisions detected in renaming plan."
            GuiManager.BtnExecute.Enabled := false
        } else if (GuiManager.CurrentPlan.Length > 0) {
            GuiManager.StatusText.Value := Format("Plan verified: {1} items ready.", GuiManager.CurrentPlan.Length)
            GuiManager.BtnExecute.Enabled := true
        }
    }

    static MoveSelected(delta) {
        row := GuiManager.LV.GetNext()
        if (!row || GuiManager.CurrentFiles.Length <= 1) {
            return
        }

        targetRow := row + delta
        if (targetRow < 1 || targetRow > GuiManager.CurrentFiles.Length) {
            return
        }

        temp := GuiManager.CurrentFiles[row]
        GuiManager.CurrentFiles[row] := GuiManager.CurrentFiles[targetRow]
        GuiManager.CurrentFiles[targetRow] := temp

        GuiManager.UpdateListView()
        GuiManager.LV.Modify(targetRow, "Select Focus")
    }

    static MoveToExtreme(toTop) {
        row := GuiManager.LV.GetNext()
        if (!row || GuiManager.CurrentFiles.Length <= 1) {
            return
        }

        item := GuiManager.CurrentFiles.RemoveAt(row)
        if (toTop) {
            GuiManager.CurrentFiles.InsertAt(1, item)
            targetRow := 1
        } else {
            GuiManager.CurrentFiles.Push(item)
            targetRow := GuiManager.CurrentFiles.Length
        }

        GuiManager.UpdateListView()
        GuiManager.LV.Modify(targetRow, "Select Focus")
    }

    static ReverseList() {
        if (GuiManager.CurrentFiles.Length <= 1) {
            return
        }
        reversed := []
        idx := GuiManager.CurrentFiles.Length
        while (idx >= 1) {
            reversed.Push(GuiManager.CurrentFiles[idx])
            idx--
        }
        GuiManager.CurrentFiles := reversed
        GuiManager.UpdateListView()
    }

    static SortNatural() {
        if (GuiManager.CurrentFiles.Length <= 1) {
            return
        }
        n := GuiManager.CurrentFiles.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (ExplorerHelper.NaturalCompare(GuiManager.CurrentFiles[j], GuiManager.CurrentFiles[j + 1]) > 0) {
                    temp := GuiManager.CurrentFiles[j]
                    GuiManager.CurrentFiles[j] := GuiManager.CurrentFiles[j + 1]
                    GuiManager.CurrentFiles[j + 1] := temp
                }
            }
        }
        GuiManager.UpdateListView()
    }

    static RemoveSelected() {
        row := GuiManager.LV.GetNext()
        if (!row || GuiManager.CurrentFiles.Length == 0) {
            return
        }
        GuiManager.CurrentFiles.RemoveAt(row)
        GuiManager.UpdateListView()
    }

    static ClearAll() {
        GuiManager.CurrentFiles := []
        GuiManager.CurrentPlan := []
        GuiManager.UpdateListView()
        GuiManager.ProgressBar.Value := 0
    }

    static ExecuteBatch() {
        if (GuiManager.CurrentPlan.Length == 0) {
            return
        }

        GuiManager.BtnExecute.Enabled := false
        GuiManager.StatusText.Value := "Executing batch rename..."

        callback := (current, total, text) => (
            GuiManager.ProgressBar.Value := Integer((current / total) * 100),
            GuiManager.StatusText.Value := text
        )

        result := RenameEngine.Execute(GuiManager.CurrentPlan, callback)

        if (result.success) {
            GuiManager.ProgressBar.Value := 100
            GuiManager.StatusText.Value := Format("✓ Success: {1} items renamed.", result.renamedCount)
            MsgBox(Format("Successfully renamed {1} items.", result.renamedCount), "Sequence Renamer v1.0", "Iconi")
            
            newFiles := []
            for item in GuiManager.CurrentPlan {
                newFiles.Push(item.targetPath)
            }
            GuiManager.CurrentFiles := newFiles
            GuiManager.UpdateListView()
        } else {
            errMsg := "Batch rename failed and was rolled back.`n`nCheck Logs for details."
            MsgBox(errMsg, "Rename Error", "Icon!")
            GuiManager.StatusText.Value := "⚠️ Renaming failed. Restored to original names."
            GuiManager.BtnExecute.Enabled := true
        }
    }

    static ExecuteUndo() {
        res := TransactionManager.UndoLast()
        if (res.success) {
            MsgBox(Format("Successfully restored {1} items to their original names.", res.count), "Undo Success", "Iconi")
            GuiManager.ClearAll()
            GuiManager.StatusText.Value := Format("Undo completed: {1} items restored.", res.count)
        } else {
            MsgBox("Undo failed: No previous transactions found or files were moved.", "Undo Failed", "Icon!")
        }
    }
}


Logger.Init()
TransactionManager.Init()
OnError(GlobalErrorHandler)
A_TrayMenu.Delete()
A_TrayMenu.Add('Open Renamer GUI (Ctrl+Shift+R)', (*) => GuiManager.Show())
A_TrayMenu.Add('Capture Active Explorer Selection', (*) => GuiManager.CaptureExplorerSelection())
A_TrayMenu.Add('Undo Last Batch (Ctrl+Shift+U)', (*) => GuiManager.ExecuteUndo())
A_TrayMenu.Add()
A_TrayMenu.Add('View Logs Folder', (*) => Run(A_ScriptDir . '\\Logs'))
A_TrayMenu.Add('Exit', (*) => ExitApp())
A_TrayMenu.Default := 'Open Renamer GUI (Ctrl+Shift+R)'
try {
    TrayTip('Press Ctrl+Shift+R in Explorer to rename selected files in order.', 'Sequence Renamer v1.0 Active', 1)
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
    Logger.Fatal('Unhandled system exception: ' . err.Message . ' at line ' . err.Line . ' in ' . err.File, 'GlobalErrorHandler')
    MsgBox(Format('An unexpected error occurred in Sequence Renamer v1.0:`n`n{1}`n`nFile: {2} (Line {3})', err.Message, err.File, err.Line), 'Sequence Renamer v1.0 - Fault', 'Icon!')
    return true
}
