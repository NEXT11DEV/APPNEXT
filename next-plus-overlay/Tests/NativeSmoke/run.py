"""Exercises the actual C++ bridge using disposable non-Apple test identities.
This validates archive/signature generation, not acceptance by a physical iPhone.
"""
import datetime, os, pathlib, plistlib, shutil, struct, subprocess, tempfile, zipfile
root=pathlib.Path.cwd()
def run(args, **kwargs): return subprocess.run([str(x) for x in args], check=True, **kwargs)
ssl=pathlib.Path(subprocess.check_output(['brew','--prefix','openssl@3'],text=True).strip())
openssl=ssl/'bin/openssl'
with tempfile.TemporaryDirectory(prefix='next-smoke-') as scratch:
 d=pathlib.Path(scratch);objs=[]
 for source in (root/'vendor/zsign/third-party/minizip').glob('*.c'):
  if source.name not in ['ioapi.c','unzip.c','zip.c']:continue
  obj=d/(source.stem+'.o');run(['clang','-c',source,'-o',obj]);objs.append(obj)
 sources=list((root/'vendor/zsign').glob('*.cpp'))+list((root/'vendor/zsign/common').glob('*.cpp'))
 sources=[s for s in sources if s.name!='zsign.cpp']
 driver=d/'bridge-smoke'
 run(['clang++','-std=c++11','-Wno-deprecated-declarations','-DZSIGN_VERSION="test"',
      '-I'+str(root/'Bridge'),'-I'+str(root/'vendor/zsign'),'-I'+str(root/'vendor/zsign/common'),
      '-I'+str(ssl/'include'), root/'Bridge/zsign_wrapper.cpp',root/'Tests/NativeSmoke/driver.cpp',*sources,*objs,
      '-L'+str(ssl/'lib'),'-lssl','-lcrypto','-lz','-framework','CoreFoundation','-o',driver])
 def cmd(*args):run([openssl,*args],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 cmd('req','-x509','-newkey','rsa:2048','-nodes','-keyout',d/'ca.key','-out',d/'ca.pem','-days','2','-subj','/CN=NEXT Disposable Test CA')
 cmd('req','-newkey','rsa:2048','-nodes','-keyout',d/'leaf.key','-out',d/'leaf.csr','-subj','/CN=NEXT Disposable Test/OU=NEXTTEST01/O=Test')
 cmd('x509','-req','-in',d/'leaf.csr','-CA',d/'ca.pem','-CAkey',d/'ca.key','-CAcreateserial','-out',d/'leaf.pem','-days','1')
 cmd('x509','-in',d/'leaf.pem','-outform','DER','-out',d/'leaf.der')
 for name,password in [('protected','test-only'),('empty','')]:
  cmd('pkcs12','-export','-inkey',d/'leaf.key','-in',d/'leaf.pem','-certfile',d/'ca.pem','-out',d/(name+'.p12'),'-passout','pass:'+password)
 now=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
 profile=dict(Name='NEXT Test Fixture',UUID='00000000-0000-0000-0000-000000000001',TeamIdentifier=['NEXTTEST01'],ApplicationIdentifierPrefix=['NEXTTEST01'],DeveloperCertificates=[(d/'leaf.der').read_bytes()],CreationDate=now,ExpirationDate=now+datetime.timedelta(days=1),ProvisionsAllDevices=True,Entitlements={'application-identifier':'NEXTTEST01.*','com.apple.developer.team-identifier':'NEXTTEST01','get-task-allow':False,'keychain-access-groups':['NEXTTEST01.*']})
 (d/'profile.plist').write_bytes(plistlib.dumps(profile))
 cmd('cms','-sign','-binary','-nodetach','-in',d/'profile.plist','-signer',d/'leaf.pem','-inkey',d/'leaf.key','-outform','DER','-out',d/'test.mobileprovision')
 app=d/'Payload/Smoke.app';app.mkdir(parents=True)
 (app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='app.nextplus.smoke',CFBundleExecutable='Smoke',CFBundleName='Smoke',CFBundleVersion='1',CFBundleShortVersionString='1.0',CFBundlePackageType='APPL',MinimumOSVersion='16.4')))
 (d/'main.c').write_text('int main(void) { return 0; }\n')
 sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
 run(['xcrun','clang','-target','arm64-apple-ios16.4','-isysroot',sdk,d/'main.c','-o',app/'Smoke'])
 (app/'resource.txt').write_text('NEXT signing test resource')
 with zipfile.ZipFile(d/'input.ipa','w',zipfile.ZIP_DEFLATED) as z:
  for p in (d/'Payload').rglob('*'):
   if p.is_file():z.write(p,p.relative_to(d))
 def sign(p12,password,out,source='input.ipa'):
  work=d/('work-'+out);work.mkdir()
  return subprocess.run([str(driver),str(d/source),str(d/p12),password,str(d/'test.mobileprovision'),str(d/out),str(work)])
 for name,password in [('protected','test-only'),('empty','')]:
  output=name+'.ipa';assert sign(name+'.p12',password,output).returncode==0
  with zipfile.ZipFile(d/output) as z:
   assert z.read('Payload/Smoke.app/embedded.mobileprovision')==(d/'test.mobileprovision').read_bytes()
   resources=plistlib.loads(z.read('Payload/Smoke.app/_CodeSignature/CodeResources'))
   assert 'resource.txt' in resources.get('files2',resources.get('files',{}))
   assert plistlib.loads(z.read('Payload/Smoke.app/Info.plist'))['CFBundleIdentifier']=='app.nextplus.smoke'
   signed=z.read('Payload/Smoke.app/Smoke');assert b'\xfa\xde\x0c\xc0' in signed
   verify=d/('verify-'+name);z.extractall(verify)
  run(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',verify/'Payload/Smoke.app'])
  print('PASS native bridge: '+name+' password IPA signing')
 assert sign('protected.p12','wrong','wrong.ipa').returncode!=0
 (d/'invalid.ipa').write_text('not an IPA')
 assert sign('empty.p12','','invalid-output.ipa','invalid.ipa').returncode!=0
 print('PASS native bridge: rejects wrong password and invalid archive')
