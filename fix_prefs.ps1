# One-time elevated edit: suppress the "no video engine" dialog and set memory size
$p = "C:\Program Files\Tracker\tracker.prefs"
$xml = Get-Content $p -Raw
if ($xml -notmatch 'warn_no_engine') {
    $ins = "    <property name=`"warn_no_engine`" type=`"boolean`">false</property>`n    <property name=`"memory_size`" type=`"int`">2048</property>`n</object>"
    $xml = $xml -replace '</object>', $ins
}
if ($xml -notmatch 'warn_xuggle_error') {
    $ins = "    <property name=`"warn_xuggle_error`" type=`"boolean`">false</property>`n</object>"
    $xml = $xml -replace '</object>', $ins
}
Set-Content $p -Value $xml -Encoding UTF8
