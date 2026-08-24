# Locations of the portable toolchain, shared by build.ps1 / run.ps1 / verify.ps1.
# Both tools live outside this project so other MSX projects can share them.

$ToolsRoot  = "D:\my\8bit\msx\tools"
$SJASMPLUS  = Join-Path $ToolsRoot "sjasmplus\sjasmplus-1.23.1.win\sjasmplus.exe"
$OPENMSX    = Join-Path $ToolsRoot "openmsx\openmsx.exe"

# C-BIOS_MSX2 is the reference MSX2 config bundled with openMSX; it needs no
# real machine ROMs. Boosted_MSX2_EN is the same BIOS with more RAM and a disk
# drive if you ever need them.
$MSX_MACHINE = "C-BIOS_MSX2"

foreach ($t in @($SJASMPLUS, $OPENMSX)) {
    if (-not (Test-Path $t)) { throw "tool not found: $t" }
}
