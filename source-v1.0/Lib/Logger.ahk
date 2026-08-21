#Requires AutoHotkey v2.0+

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