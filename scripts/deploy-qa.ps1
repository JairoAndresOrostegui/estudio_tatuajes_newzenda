$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
function Run-Checked { param([scriptblock]$Action) & $Action; if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" } }
Run-Checked { flutter pub get }
Run-Checked { flutter analyze }
Run-Checked { flutter test }
Run-Checked { npm --prefix functions ci }
Run-Checked { npm --prefix functions test }
Run-Checked { firebase emulators:exec --only firestore --project demo-findink 'npm --prefix functions run test:rules' }
Run-Checked { flutter build web --release --dart-define-from-file=config/firebase.qa.json }
Run-Checked { flutter build apk --release --dart-define-from-file=config/firebase.qa.json }
New-Item -ItemType Directory -Path 'build/web/downloads' -Force | Out-Null
Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination 'build/web/downloads/findink-qa.apk'
Run-Checked { firebase deploy --only 'firestore,functions,hosting' --project estudio-tatuajes-newzenda --non-interactive }
