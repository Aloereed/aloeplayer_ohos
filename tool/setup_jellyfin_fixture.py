"""Initialize only the generated loopback fixture, never a user's media server."""
from pathlib import Path
import json
import secrets
import time
import urllib.parse
import urllib.request
import urllib.error
import argparse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--kind', choices=['jellyfin', 'emby'], default='jellyfin')
kind = parser.parse_args().kind
RUNTIME = ROOT / 'build/media-server-fixtures' / ('jellyfin-12-runtime' if kind == 'jellyfin' else 'emby-4.10-runtime')
state = json.loads((RUNTIME / 'fixture.json').read_text(encoding='utf-8-sig'))
base = state['url']
assert urllib.parse.urlparse(base).hostname == '127.0.0.1'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
headers = {'Content-Type':'application/json', 'X-Emby-Authorization':
           'MediaBrowser Client="AloeFixture", Device="Desktop", DeviceId="aloe-fixture", Version="4.0.1"'}
headers['Authorization'] = headers['X-Emby-Authorization']

def api(path, method='GET', data=None, query=None):
    url = base + '/' + path
    if query:
        url += '?' + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers=headers, method=method,
        data=None if data is None else json.dumps(data).encode())
    try:
        with opener.open(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors='replace')[:2000]
        if data:
            for key in ['Pw','Password']:
                if data.get(key): detail = detail.replace(data[key], '[redacted]')
        raise RuntimeError(f'{method} {path}: HTTP {error.code}: {detail}') from None

auth_path = RUNTIME / 'test-auth.json'
info = api('System/Info/Public')
if kind == 'jellyfin':
    assert info['ProductName'] == 'Jellyfin Server'
    wizard_completed = info['StartupWizardCompleted']
else:
    assert info['Version'].startswith('4.10.')
    wizard_completed = ET.parse(RUNTIME / 'config/system.xml').getroot().findtext('IsStartupWizardCompleted') == 'true'
if not wizard_completed:
    api('Startup/User')
    auth = {'username':'aloe-fixture', 'password':secrets.token_hex(20)}
    auth_path.write_text(json.dumps(auth), encoding='utf-8')
    api('Startup/User','POST',{'Name':auth['username'],'Password':auth['password']})
    api('Startup/RemoteAccess','POST',{'EnableRemoteAccess':False, 'EnableAutomaticPortMapping':False})
    api('Startup/Complete','POST',{})
else:
    auth = json.loads(auth_path.read_text())
login = api('Users/AuthenticateByName','POST',{'Username':auth['username'],'Pw':auth['password']})
headers['X-Emby-Token'] = login['AccessToken']
headers['Authorization'] += ', Token="' + login['AccessToken'] + '"'
auth.update({'url':base,'token':login['AccessToken'],'userId':login['User']['Id'],'version':info['Version']})
auth_path.write_text(json.dumps(auth),encoding='utf-8')
config = api('System/Configuration')
config.update({'ServerName':'Aloe generated fixture only','MinResumeDurationSeconds':1,
               'MinResumePct':1,'MaxResumePct':95})
api('System/Configuration','POST',config)
existing = {library['Name'] for library in api('Library/VirtualFolders')}
for folder, collection_type in [('Movies','movies'),('Shows','tvshows')]:
    name = 'Aloe Fixture ' + folder
    if name not in existing:
        options = {'PathInfos':[{'Path':str(ROOT / 'build/media-server-fixtures/library' / folder)}],
          'EnableRealtimeMonitor':False,'EnableChapterImageExtraction':False,
          'MinResumeDurationSeconds':1,'MinResumePct':1,'MaxResumePct':95,
          'TypeOptions':[{'Type':t,'MetadataFetchers':[],'ImageFetchers':[]} for t in ['Movie','Series','Season','Episode']],
          'LocalMetadataReaderOrder':['Nfo']}
        api('Library/VirtualFolders','POST',{'LibraryOptions':options},
            {'Name':name,'CollectionType':collection_type,'RefreshLibrary':'true'})
if kind == 'emby':
    # Emby stores resume thresholds per library, unlike Jellyfin's global setting.
    for library in api('Library/VirtualFolders'):
        assert library['Name'].startswith('Aloe Fixture ')
        options = library['LibraryOptions']
        options.update({'MinResumeDurationSeconds':1,'MinResumePct':1,'MaxResumePct':95})
        api('Library/VirtualFolders/LibraryOptions', 'POST',
            {'Id':library['ItemId'], 'LibraryOptions':options})
api('Library/Refresh','POST',{})
for attempt in range(30):
    items = api('Items',query={'UserId':auth['userId'],'Recursive':'true','Fields':'MediaSources,Overview'})['Items']
    episodes = [i for i in items if i['Type'] == 'Episode']
    movies = [i for i in items if i['Type'] == 'Movie']
    if len(episodes) >= 3 and movies:
        (RUNTIME / 'items.json').write_text(json.dumps(items,ensure_ascii=False),encoding='utf-8')
        print(json.dumps({'result':'READY','version':info['Version'],'movieItems':len(movies),
                          'episodes':len(episodes),'loopbackPort':state['port']}))
        break
    time.sleep(1)
else:
    raise RuntimeError('Fixture scan did not finish within 30 seconds')
