import hashlib, zipfile, time, io, os

# ---- A) isolate the ZIP timestamp axis: identical part bytes, different entry date_time
def build(path, dt):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, b in (("[Content_Types].xml", b"<Types/>"), ("word/document.xml", b"<w:document/>")):
            zi = zipfile.ZipInfo(n, date_time=dt)
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, b)
def sha(p): return hashlib.sha256(open(p,"rb").read()).hexdigest()
build("t1.zip", (2026,9,21,10,0,0)); build("t2.zip", (2026,9,21,10,0,2))
print("A) stdlib zip, IDENTICAL part bytes, entry date_time differs by 2s")
print("   t1", sha("t1.zip")); print("   t2", sha("t2.zip"))
print("   container sha equal:", sha("t1.zip")==sha("t2.zip"))
pa={n:hashlib.sha256(zipfile.ZipFile("t1.zip").read(n)).hexdigest() for n in zipfile.ZipFile("t1.zip").namelist()}
pb={n:hashlib.sha256(zipfile.ZipFile("t2.zip").read(n)).hexdigest() for n in zipfile.ZipFile("t2.zip").namelist()}
print("   per-part content equal:", pa==pb)
# show the raw local-header mtime field bytes
raw1=open("t1.zip","rb").read(); raw2=open("t2.zip","rb").read()
print("   local hdr [10:14] (mod time/date) t1:", raw1[10:14].hex(), " t2:", raw2[10:14].hex())
d=[i for i in range(min(len(raw1),len(raw2))) if raw1[i]!=raw2[i]]
print("   differing byte offsets:", d)

# ---- B) python-docx, two saves 3s apart
import docx
def mkd(p):
    d = docx.Document(); d.add_paragraph("hello"); d.save(p)
mkd("a.docx"); time.sleep(3); mkd("b.docx")
print("\nB) python-docx two saves 3s apart")
print("   whole-file sha equal:", sha("a.docx")==sha("b.docx"), sha("a.docx")[:16], sha("b.docx")[:16])
A={i.filename:(hashlib.sha256(zipfile.ZipFile("a.docx").read(i.filename)).hexdigest(), i.date_time) for i in zipfile.ZipFile("a.docx").infolist()}
B={i.filename:(hashlib.sha256(zipfile.ZipFile("b.docx").read(i.filename)).hexdigest(), i.date_time) for i in zipfile.ZipFile("b.docx").infolist()}
vol=[n for n in A if A[n][0]!=B[n][0]]
print("   content-volatile parts:", vol)
print("   zip date_time differs on:", [n for n in A if A[n][1]!=B[n][1]])
print("   sample date_time a/b:", list(A.items())[0][1][1], list(B.items())[0][1][1])
print("\n   a.docx docProps/core.xml:\n", zipfile.ZipFile("a.docx").read("docProps/core.xml").decode()[:600])
print("\n   a.docx docProps/app.xml:\n", zipfile.ZipFile("a.docx").read("docProps/app.xml").decode()[:600])
