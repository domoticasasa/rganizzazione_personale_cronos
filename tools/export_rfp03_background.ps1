param(
  [Parameter(Mandatory = $true)][string]$XlsxPath,
  [Parameter(Mandatory = $true)][string]$PdfPath
)

$ErrorActionPreference = "Stop"
$excel = $null
$wb = $null
try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $wb = $excel.Workbooks.Open($XlsxPath)
  $xlTypePDF = 0
  $wb.ExportAsFixedFormat($xlTypePDF, $PdfPath, 0, $true, $false, $false, $false, $false)
  $wb.Close($false)
  $excel.Quit()
  Write-Output "OK $PdfPath"
}
finally {
  if ($wb -ne $null) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null }
  if ($excel -ne $null) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
