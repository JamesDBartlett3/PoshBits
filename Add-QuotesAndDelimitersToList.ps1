Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Quote and Delimit List"
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = "CenterScreen"

# Label for input
$labelInput = New-Object System.Windows.Forms.Label
$labelInput.Text = "List of items (whitespace or newline separated):"
$labelInput.Location = New-Object System.Drawing.Point(10, 10)
$labelInput.Size = New-Object System.Drawing.Size(460, 20)
$form.Controls.Add($labelInput)

# TextBox for list input
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Multiline = $true
$textBox.ScrollBars = "Vertical"
$textBox.Location = New-Object System.Drawing.Point(10, 35)
$textBox.Size = New-Object System.Drawing.Size(460, 150)
$form.Controls.Add($textBox)

# Quote style dropdown
$labelQuote = New-Object System.Windows.Forms.Label
$labelQuote.Text = "Quote style:"
$labelQuote.Location = New-Object System.Drawing.Point(10, 195)
$form.Controls.Add($labelQuote)

$comboQuote = New-Object System.Windows.Forms.ComboBox
$comboQuote.Items.AddRange(@("Single", "Double"))
$comboQuote.SelectedIndex = 0
$comboQuote.Location = New-Object System.Drawing.Point(120, 190)  # Moved right
$form.Controls.Add($comboQuote)

# Delimiter dropdown
$labelDelimiter = New-Object System.Windows.Forms.Label
$labelDelimiter.Text = "Delimiter:"
$labelDelimiter.Location = New-Object System.Drawing.Point(10, 225)
$form.Controls.Add($labelDelimiter)

$comboDelimiter = New-Object System.Windows.Forms.ComboBox
$comboDelimiter.Items.AddRange(@("Comma", "Semicolon"))
$comboDelimiter.SelectedIndex = 0
$comboDelimiter.Location = New-Object System.Drawing.Point(120, 220)  # Moved right
$form.Controls.Add($comboDelimiter)

# OK button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "Process"
$okButton.Location = New-Object System.Drawing.Point(10, 260)
$okButton.Add_Click({
    $items = $textBox.Text -split "\s+"
    $quoteChar = if ($comboQuote.SelectedItem -eq "Single") { "'" } else { '"' }
    $delimiter = if ($comboDelimiter.SelectedItem -eq "Comma") { "," } else { ";" }

    $quotedItems = $items | Where-Object { $_ -ne "" } | ForEach-Object { "$quoteChar$_$quoteChar" }
    $result = [string]::Join($delimiter + " ", $quotedItems)

    # Result form
    $resultForm = New-Object System.Windows.Forms.Form
    $resultForm.Text = "Formatted Result"
    $resultForm.Size = New-Object System.Drawing.Size(520, 300)  # Increased width
    $resultForm.StartPosition = "CenterScreen"

    $resultBox = New-Object System.Windows.Forms.TextBox
    $resultBox.Multiline = $true
    $resultBox.ReadOnly = $true
    $resultBox.ScrollBars = "Vertical"
    $resultBox.Text = $result
    $resultBox.Location = New-Object System.Drawing.Point(10, 10)
    $resultBox.Size = New-Object System.Drawing.Size(480, 200)  # Adjusted width
    $resultForm.Controls.Add($resultBox)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = "Copy to Clipboard"
    $copyButton.Size = New-Object System.Drawing.Size(150, 30)  # Explicit size
    $copyButton.Location = New-Object System.Drawing.Point(10, 220)  # Left-aligned
    $copyButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($resultBox.Text) })
    $resultForm.Controls.Add($copyButton)


    $resultForm.ShowDialog()
})
$form.Controls.Add($okButton)

# Show the form
$form.ShowDialog()
