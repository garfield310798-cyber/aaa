Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Variables globales
$script:solution = New-Object 'int[,]' 9,9
$script:cells = New-Object 'System.Windows.Forms.TextBox[,]' 9,9

# Funcion para generar un tablero valido de sudoku
function New-SudokuBoard {
    $base = @(
        @(1,2,3,4,5,6,7,8,9),
        @(4,5,6,7,8,9,1,2,3),
        @(7,8,9,1,2,3,4,5,6),
        @(2,3,4,5,6,7,8,9,1),
        @(5,6,7,8,9,1,2,3,4),
        @(8,9,1,2,3,4,5,6,7),
        @(3,4,5,6,7,8,9,1,2),
        @(6,7,8,9,1,2,3,4,5),
        @(9,1,2,3,4,5,6,7,8)
    )

    $board = New-Object 'int[,]' 9,9
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $board[$i,$j] = $base[$i][$j]
        }
    }

    # Mapeo aleatorio de numeros 1-9
    $mapping = 1..9 | Get-Random -Count 9
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $board[$i,$j] = $mapping[$board[$i,$j] - 1]
        }
    }

    # Intercambiar filas dentro de bandas
    for ($band = 0; $band -lt 3; $band++) {
        $shuffle = 0..2 | Get-Random -Count 3
        $temp = New-Object 'int[,]' 3,9
        for ($r = 0; $r -lt 3; $r++) {
            for ($c = 0; $c -lt 9; $c++) {
                $temp[$r,$c] = $board[$band * 3 + $shuffle[$r], $c]
            }
        }
        for ($r = 0; $r -lt 3; $r++) {
            for ($c = 0; $c -lt 9; $c++) {
                $board[$band * 3 + $r, $c] = $temp[$r,$c]
            }
        }
    }

    # Intercambiar columnas dentro de pilas
    for ($stack = 0; $stack -lt 3; $stack++) {
        $shuffle = 0..2 | Get-Random -Count 3
        $temp = New-Object 'int[,]' 9,3
        for ($c = 0; $c -lt 3; $c++) {
            for ($r = 0; $r -lt 9; $r++) {
                $temp[$r,$c] = $board[$r, $stack * 3 + $shuffle[$c]]
            }
        }
        for ($c = 0; $c -lt 3; $c++) {
            for ($r = 0; $r -lt 9; $r++) {
                $board[$r, $stack * 3 + $c] = $temp[$r,$c]
            }
        }
    }

    # Intercambiar bandas de filas
    $bandShuffle = 0..2 | Get-Random -Count 3
    $tempBoard = New-Object 'int[,]' 9,9
    for ($b = 0; $b -lt 3; $b++) {
        for ($r = 0; $r -lt 3; $r++) {
            for ($c = 0; $c -lt 9; $c++) {
                $tempBoard[$b * 3 + $r, $c] = $board[$bandShuffle[$b] * 3 + $r, $c]
            }
        }
    }
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $board[$i,$j] = $tempBoard[$i,$j]
        }
    }

    # Intercambiar pilas de columnas
    $stackShuffle = 0..2 | Get-Random -Count 3
    for ($s = 0; $s -lt 3; $s++) {
        for ($c = 0; $c -lt 3; $c++) {
            for ($r = 0; $r -lt 9; $r++) {
                $tempBoard[$r, $s * 3 + $c] = $board[$r, $stackShuffle[$s] * 3 + $c]
            }
        }
    }
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $board[$i,$j] = $tempBoard[$i,$j]
        }
    }

    return ,$board
}

# Generar puzzle segun dificultad
function Generate-Sudoku {
    param([string]$difficulty)

    $script:solution = New-SudokuBoard

    $cellsToRemove = switch ($difficulty) {
        "Facil"   { 35 }
        "Medio"   { 45 }
        "Dificil" { 55 }
        default   { 40 }
    }

    $positions = @()
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $positions += ,@($i, $j)
        }
    }
    $positionsToRemove = $positions | Get-Random -Count $cellsToRemove

    $hidden = New-Object 'bool[,]' 9,9
    foreach ($pos in $positionsToRemove) {
        $hidden[$pos[0], $pos[1]] = $true
    }

    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $cell = $script:cells[$i,$j]
            $cell.ReadOnly = $false
            if ($hidden[$i,$j]) {
                $cell.Text = ""
                $cell.BackColor = [System.Drawing.Color]::White
                $cell.ForeColor = [System.Drawing.Color]::Blue
            } else {
                $cell.Text = $script:solution[$i,$j].ToString()
                $cell.ReadOnly = $true
                $cell.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
                $cell.ForeColor = [System.Drawing.Color]::Black
            }
        }
    }
}

# Comprobar solucion del usuario
function Check-Sudoku {
    $correct = $true
    $complete = $true

    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $cell = $script:cells[$i,$j]
            if ($cell.ReadOnly) { continue }

            $text = $cell.Text.Trim()

            if ([string]::IsNullOrEmpty($text)) {
                $cell.BackColor = [System.Drawing.Color]::White
                $complete = $false
                continue
            }

            $value = 0
            if (-not [int]::TryParse($text, [ref]$value)) {
                $cell.BackColor = [System.Drawing.Color]::LightPink
                $correct = $false
                continue
            }

            if ($value -ne $script:solution[$i,$j]) {
                $cell.BackColor = [System.Drawing.Color]::LightPink
                $correct = $false
            } else {
                $cell.BackColor = [System.Drawing.Color]::LightGreen
            }
        }
    }

    if ($correct -and $complete) {
        [System.Windows.Forms.MessageBox]::Show("Felicidades! Has resuelto el Sudoku correctamente.", "Sudoku Completado", "OK", "Information") | Out-Null
    } elseif (-not $complete) {
        [System.Windows.Forms.MessageBox]::Show("Aun quedan celdas vacias. Las celdas en rojo son incorrectas, en verde son correctas.", "Incompleto", "OK", "Warning") | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("Hay errores. Las celdas en rojo son incorrectas, en verde son correctas.", "Errores Encontrados", "OK", "Warning") | Out-Null
    }
}

# Formulario principal
$form = New-Object System.Windows.Forms.Form
$form.Text = "Sudoku - PowerShell"
$form.Size = New-Object System.Drawing.Size(540, 720)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "SUDOKU"
$titleLabel.Font = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(0, 10)
$titleLabel.Size = New-Object System.Drawing.Size(540, 35)
$titleLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($titleLabel)

$diffLabel = New-Object System.Windows.Forms.Label
$diffLabel.Text = "Dificultad:"
$diffLabel.Location = New-Object System.Drawing.Point(20, 55)
$diffLabel.Size = New-Object System.Drawing.Size(75, 25)
$diffLabel.Font = New-Object System.Drawing.Font("Arial", 10)
$form.Controls.Add($diffLabel)

$diffCombo = New-Object System.Windows.Forms.ComboBox
$diffCombo.Location = New-Object System.Drawing.Point(100, 53)
$diffCombo.Size = New-Object System.Drawing.Size(120, 25)
$diffCombo.DropDownStyle = "DropDownList"
$diffCombo.Items.AddRange(@("Facil", "Medio", "Dificil"))
$diffCombo.SelectedIndex = 0
$diffCombo.Font = New-Object System.Drawing.Font("Arial", 10)
$form.Controls.Add($diffCombo)

$genButton = New-Object System.Windows.Forms.Button
$genButton.Text = "Generar Nuevo Sudoku"
$genButton.Location = New-Object System.Drawing.Point(240, 50)
$genButton.Size = New-Object System.Drawing.Size(180, 32)
$genButton.BackColor = [System.Drawing.Color]::LightBlue
$genButton.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$genButton.Add_Click({
    Generate-Sudoku -difficulty $diffCombo.SelectedItem
})
$form.Controls.Add($genButton)

# Panel del tablero
$gridPanel = New-Object System.Windows.Forms.Panel
$gridPanel.Location = New-Object System.Drawing.Point(20, 95)
$gridPanel.Size = New-Object System.Drawing.Size(480, 480)
$gridPanel.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($gridPanel)

# Crear cuadricula 9x9
$cellSize = 50
for ($i = 0; $i -lt 9; $i++) {
    for ($j = 0; $j -lt 9; $j++) {
        $cell = New-Object System.Windows.Forms.TextBox
        $cell.Size = New-Object System.Drawing.Size($cellSize, $cellSize)

        $x = $j * $cellSize + $j
        $y = $i * $cellSize + $i
        if ($j -ge 3) { $x += 2 }
        if ($j -ge 6) { $x += 2 }
        if ($i -ge 3) { $y += 2 }
        if ($i -ge 6) { $y += 2 }

        $cell.Location = New-Object System.Drawing.Point($x, $y)
        $cell.TextAlign = "Center"
        $cell.Font = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
        $cell.MaxLength = 1
        $cell.BackColor = [System.Drawing.Color]::White
        $cell.BorderStyle = "FixedSingle"

        $cell.Add_KeyPress({
            param($sender, $e)
            if (-not [char]::IsDigit($e.KeyChar) -and $e.KeyChar -ne [char]8) {
                $e.Handled = $true
            }
            if ($e.KeyChar -eq '0') {
                $e.Handled = $true
            }
        })

        $script:cells[$i,$j] = $cell
        $gridPanel.Controls.Add($cell)
    }
}

# Boton Comprobar
$checkButton = New-Object System.Windows.Forms.Button
$checkButton.Text = "COMPROBAR"
$checkButton.Location = New-Object System.Drawing.Point(160, 595)
$checkButton.Size = New-Object System.Drawing.Size(200, 50)
$checkButton.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$checkButton.BackColor = [System.Drawing.Color]::LightGreen
$checkButton.Add_Click({ Check-Sudoku })
$form.Controls.Add($checkButton)

# Boton Limpiar
$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "Limpiar"
$clearButton.Location = New-Object System.Drawing.Point(20, 605)
$clearButton.Size = New-Object System.Drawing.Size(120, 30)
$clearButton.Font = New-Object System.Drawing.Font("Arial", 9)
$clearButton.Add_Click({
    for ($i = 0; $i -lt 9; $i++) {
        for ($j = 0; $j -lt 9; $j++) {
            $cell = $script:cells[$i,$j]
            if (-not $cell.ReadOnly) {
                $cell.Text = ""
                $cell.BackColor = [System.Drawing.Color]::White
            }
        }
    }
})
$form.Controls.Add($clearButton)

# Boton Ver Solucion
$solveButton = New-Object System.Windows.Forms.Button
$solveButton.Text = "Ver Solucion"
$solveButton.Location = New-Object System.Drawing.Point(380, 605)
$solveButton.Size = New-Object System.Drawing.Size(120, 30)
$solveButton.Font = New-Object System.Drawing.Font("Arial", 9)
$solveButton.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show("Estas seguro de que deseas ver la solucion?", "Confirmar", "YesNo", "Question")
    if ($result -eq "Yes") {
        for ($i = 0; $i -lt 9; $i++) {
            for ($j = 0; $j -lt 9; $j++) {
                $cell = $script:cells[$i,$j]
                if (-not $cell.ReadOnly) {
                    $cell.Text = $script:solution[$i,$j].ToString()
                    $cell.ForeColor = [System.Drawing.Color]::Red
                }
            }
        }
    }
})
$form.Controls.Add($solveButton)

# Generar sudoku inicial
Generate-Sudoku -difficulty "Facil"

# Mostrar formulario
[void]$form.ShowDialog()
