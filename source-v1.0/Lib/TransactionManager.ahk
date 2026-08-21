#Requires AutoHotkey v2.0+

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
