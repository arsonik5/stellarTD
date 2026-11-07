import json, urllib.request, os, zipfile, io, sys
IDS = ["Ground091","Ground097","Rock030","Rock035","Rock051","Rock061","Rock062","Snow010A","Snow015","Ice002",
       "Gravel040","Ground110","Ground102","Rocks022","Ground080","Ground068","Rock058","Lava001","Snow008A","Rock063"]
for aid in IDS:
    if os.path.isdir(aid) and os.listdir(aid):
        print("have", aid); continue
    u = f"https://ambientcg.com/api/v2/full_json?id={aid}&include=downloadData"
    d = json.load(urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "stellar-td-lab"})))
    a = d["foundAssets"][0]
    dl = None
    for cat in a["downloadFolders"]["default"]["downloadFiletypeCategories"].values():
        for f in cat["downloads"]:
            if f["attribute"] == "1K-JPG":
                dl = f
    if dl is None:
        print("no 1K-JPG", aid); continue
    data = urllib.request.urlopen(urllib.request.Request(dl["fullDownloadPath"], headers={"User-Agent": "stellar-td-lab"})).read()
    os.makedirs(aid, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(data)).extractall(aid)
    print("got", aid, len(data)//1024, "KB", sorted(os.listdir(aid)))
open("SOURCES.md","w").write("# CC0 sources\nAll from ambientCG (https://ambientcg.com), license CC0 1.0. 1K-JPG sets.\n\n" + "\n".join(f"- {i}: https://ambientcg.com/view?id={i}" for i in IDS) + "\n")
