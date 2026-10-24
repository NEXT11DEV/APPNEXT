"""Live dependency check, using the same request headers as InstallController."""
import plistlib,urllib.request,urllib.parse
payload='http://127.0.0.1:49152/app.ipa'
url='https://api.palera.in/genPlist?'+urllib.parse.urlencode(dict(bundleid='app.idkplus.smoke',name='idk plus',version='1',fetchurl=payload))
request=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148','Accept':'application/xml,text/xml,*/*'})
with urllib.request.urlopen(request,timeout=20) as response:
 assert response.status==200
 manifest=plistlib.loads(response.read())
item=manifest['items'][0]
assert item['metadata']['bundle-identifier']=='app.idkplus.smoke'
assert any(a['kind']=='software-package' and a['url']==payload for a in item['assets'])
print('PASS: live HTTPS manifest service returns the expected bundle and loopback IPA URL')

