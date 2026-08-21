#Requires AutoHotkey v2.0+

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