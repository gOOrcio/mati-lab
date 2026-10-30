# Stirling PDF (NAS)

TrueNAS Scale **catalogue app** `stirling-pdf` (train `community`), serving
`https://pdf.mati-lab.online`. PDF workbench plus each user's *My Files*
working shelf. It is not the archive; the long-term archive will be Paperless-ngx.
Design: `docs/superpowers/specs/2026-10-30-stirling-pdf-design.md` (local only).

## Layout

Dataset `bulk/stirling-pdf` (owned `568:568`, mode 755), all mounts are host paths:

| Host path | Container path | Contents |
|---|---|---|
| `/mnt/bulk/stirling-pdf/storage` | `/storage` | Server-side file storage (*My Files*), `STORAGE_LOCAL_BASEPATH` |
| `/mnt/bulk/stirling-pdf/configs` | `/configs` | `settings.yml` (holds the OIDC client secret), embedded user DB |
| `/mnt/bulk/stirling-pdf/customFiles` | `/customFiles` | Custom static files |
| `/mnt/bulk/stirling-pdf/pipeline` | `/pipeline` | Pipeline watch folders (unused) |
| `/mnt/bulk/stirling-pdf/tessdata` | `/usr/share/tessdata` | Extra OCR languages (`pol`) |
| ixVolume | `/logs` | Disposable; logs also reach Loki via Alloy |

## OCR languages

The image ships `eng osd deu fra por chi_sim` in
`/usr/share/tesseract-ocr/5/tessdata` (`TESS_BASE_PATH`). On start,
`/scripts/init.sh` copies anything mounted at `/usr/share/tessdata` into
that directory (`cp -rn`), so the mount **adds** languages and doesn't hide the
bundled ones. Only `pol` needs seeding:

```bash
# dev PC
curl -fsSL -o pol.traineddata https://github.com/tesseract-ocr/tessdata_fast/raw/main/pol.traineddata
# sha256 c4476cdbc0e33d898d32345122b7be1cbf85ace15f920f06c7714756e1ef79b2 (2026-10-30)
scp pol.traineddata truenas_admin@192.168.1.65:/tmp/
```

`truenas_admin` can't write the `568`-owned dir. Install it as root via the
temp-cron channel: a script doing
`install -o 568 -g 568 -m 644 /tmp/pol.traineddata /mnt/bulk/stirling-pdf/tessdata/`,
run with `cronjob.create` (disabled) → `cronjob.run -j` → `cronjob.delete`.

`tessdata_fast` matches the speed/accuracy class of the Debian-packaged
bundled models.

## Ownership

The container starts as root and `init-without-ocr.sh` chowns `/configs`,
`/customFiles`, `/pipeline`, `/storage`, `/logs` to `stirlingpdfuser`,
remapped by `PUID`/`PGID`. Both are set to `568` so host files stay `apps:apps`.
