#Requires AutoHotkey v2.0+

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
