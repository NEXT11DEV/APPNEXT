import pathlib,subprocess,tempfile
root=pathlib.Path.cwd()
with tempfile.TemporaryDirectory(prefix='next-performance-') as d:
 d=pathlib.Path(d)
 models=(root/'App/Services/RepositoryStore.swift').read_text().split('@MainActor\nfinal class RepositoryStore:')[0]
 (d/'Models.swift').write_text(models)
 subprocess.run(['swiftc','-swift-version','6',str(d/'Models.swift'),'App/Services/NextCatalogIndex.swift','App/Services/NextProgressThrottle.swift','App/Services/NextTransferSnapshot.swift','Tests/Performance/Checks.swift','-o',str(d/'checks')],check=True)
 subprocess.run([str(d/'checks')],check=True)

