import pathlib,subprocess,tempfile
root=pathlib.Path.cwd()
with tempfile.TemporaryDirectory(prefix='idk-source-check-') as d:
 d=pathlib.Path(d)
 source=(root/'App/Services/RepositoryStore.swift').read_text().split('@MainActor\nfinal class RepositoryStore:')[0]
 (d/'SourceModels.swift').write_text(source)
 subprocess.run(['swiftc','-swift-version','6',str(d/'SourceModels.swift'),'App/Services/NextDefaultSources.swift','Tests/Sources/Checks.swift','-o',str(d/'source-check')],check=True)
 subprocess.run([str(d/'source-check'),'App/Resources/IDKPlusCatalog.json'],check=True)
 # Compile the real service and exercise its removal guard and asynchronous bundle load.
 subprocess.run(['swiftc','-swift-version','6','App/Services/RepositoryStore.swift','App/Services/NextDefaultSources.swift','Tests/Sources/StoreChecks.swift','-o',str(d/'store-check')],check=True)
 (d/'IDKPlusCatalog.json').write_bytes((root/'App/Resources/IDKPlusCatalog.json').read_bytes())
 subprocess.run([str(d/'store-check')],check=True)
