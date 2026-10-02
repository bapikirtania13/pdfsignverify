$jars = Get-ChildItem -Path "C:\Users\djbap\.gradle\caches\modules-2\files-2.1" -Recurse -Filter "*.jar" | Where-Object { $_.FullName -match "itext|bouncycastle|slf4j" } | ForEach-Object { $_.FullName }
$cp = ".;" + ($jars -join ";")
$className = $args[0]
if (Test-Path "$className.java") {
    javac -cp $cp "$className.java"
}
& java -cp $cp $className
