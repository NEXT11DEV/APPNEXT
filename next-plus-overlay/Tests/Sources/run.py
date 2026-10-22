import pathlib,subprocess,urllib.request,tempfile
root=pathlib.Path.cwd()
with tempfile.TemporaryDirectory(prefix='next-source-check-') as d:
 d=pathlib.Path(d)
 # Compile the actual production model definitions without the app's UI service.
 source=(root/'App/Services/RepositoryStore.swift').read_text().split('@MainActor\nfinal class RepositoryStore:')[0]
 (d/'SourceModels.swift').write_text(source)
 url='https://raw.githubusercontent.com/NEXT11DEV/NEXT-SOURCE/main/NEXTDEV-ESign.json'
 (d/'source.json').write_bytes(urllib.request.urlopen(url,timeout=60).read())
 subprocess.run(['swiftc','-swift-version','6',str(d/'SourceModels.swift'),'App/Services/NextDefaultSources.swift','Tests/Sources/Checks.swift','-o',str(d/'source-check')],check=True)
 subprocess.run([str(d/'source-check'),str(d/'source.json')],check=True)
