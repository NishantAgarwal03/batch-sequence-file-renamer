#Requires AutoHotkey v2.0+

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
