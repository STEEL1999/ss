"""
Corre embebido en la app Android vía Chaquopy.
Es el mismo motor de descarga que d.py, pero sin nada de PyQt: la UI y el
manejo de hilos ahora los hace Flutter/Kotlin. Kotlin llama a estas
funciones y les pasa un callback para reportar progreso.
"""

import os
import re
import time
from urllib.parse import urlparse

import requests
import yt_dlp

# ----------------------------------------------------------------------------
# EXTRACTOR CUSTOM: mismo que el original
# ----------------------------------------------------------------------------


def extract_pimpbunny_com(page_url):
  headers = {
      "Referer": page_url,
      "User-Agent": (
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
          " (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
      ),
  }
  resp = requests.get(page_url, headers=headers, timeout=15)
  resp.raise_for_status()
  html = resp.text

  pattern = r"https?://pimpbunny\.com/[^\s\"'<>]+\.mp4(?:\?[^\s\"'<>]*)?"
  matches = re.findall(pattern, html)
  if not matches:
    return None

  options = {}
  for url in set(matches):
    if (
        "preview" in url.lower()
        or "screenshots" in url.lower()
        or "thumbs" in url.lower()
    ):
      continue
    res_match = re.search(r"_(\d+p)\.mp4", url)
    if res_match:
      options[res_match.group(1)] = url
    elif "get_file" in url:
      options["Calidad Principal"] = url

  return options if options else None


CUSTOM_EXTRACTORS = {
    "pimpbunny.com": extract_pimpbunny_com,
    "www.pimpbunny.com": extract_pimpbunny_com,
}

# Registro de descargas activas, indexado por id, para poder
# pausar/reanudar/cancelar desde Kotlin (equivalente a self.active_workers).
_ACTIVE = {}


def custom_extract(domain, url):
  fn = CUSTOM_EXTRACTORS.get(domain)
  if not fn:
    return None
  try:
    return fn(url)
  except Exception as e:
    print(f"[Custom Extractor] Error: {e}")
    return None


def probe_info(url):
  """Equivalente a probe_opts + ydl.extract_info(download=False) +
  _prompt_resolution, pero devolviendo los datos para que la UI de Flutter
  arme el selector de calidad (en vez de QInputDialog)."""
  probe_opts = {"quiet": True, "skip_download": True}
  with yt_dlp.YoutubeDL(probe_opts) as ydl:
    info = ydl.extract_info(url, download=False)

  if not info:
    return None

  formats = info.get("formats") or []
  heights = sorted(
      {
          f.get("height")
          for f in formats
          if f.get("height") and f.get("vcodec") != "none"
      },
      reverse=True,
  )

  return {
      "title": info.get("title") or "Video",
      "heights": heights,
  }


def _format_speed(bytes_per_sec):
  if not bytes_per_sec or bytes_per_sec <= 0:
    return "0 KB/s"
  if bytes_per_sec >= 1024 * 1024:
    return f"{bytes_per_sec / (1024 * 1024):.2f} MB/s"
  return f"{bytes_per_sec / 1024:.1f} KB/s"


class _DownloadState:

  def __init__(self):
    self.is_paused = False
    self.is_cancelled = False


def start_download(download_id, url, save_dir, title, format_chosen,
                    progress_callback):
  """progress_callback es un objeto Kotlin (Java interface) con métodos
  onProgress(percent, speed) y onFinished(success, message), pasado desde
  MainActivity.kt. Se ejecuta en el hilo que Kotlin haya elegido (idealmente
  un background thread, no el hilo principal)."""

  state = _DownloadState()
  _ACTIVE[download_id] = state

  def progress_hook(d):
    if state.is_cancelled:
      raise Exception("Descarga cancelada por el usuario")

    while state.is_paused:
      if state.is_cancelled:
        raise Exception("Descarga cancelada por el usuario")
      time.sleep(0.5)

    if d["status"] == "downloading":
      total = d.get("total_bytes") or d.get("total_bytes_estimate", 0)
      downloaded = d.get("downloaded_bytes", 0)
      speed = d.get("speed", 0)
      percent = int((downloaded / total) * 100) if total > 0 else 0
      progress_callback.onProgress(percent, _format_speed(speed))
    elif d["status"] == "finished":
      progress_callback.onProgress(99, "Procesando...")

  out_template = os.path.join(save_dir, "%(title)s.%(ext)s")
  ydl_opts = {
      "outtmpl": out_template,
      "format": format_chosen or "bestvideo+bestaudio/best",
      "merge_output_format": "mp4",
      "quiet": True,
      "progress_hooks": [progress_hook],
      "nocheckcertificate": True,
      "concurrent_fragment_downloads": 4,
      "buffersize": 1024 * 64,
  }

  try:
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
      ydl.download([url])
    if not state.is_cancelled:
      progress_callback.onFinished(True, "Descarga completada")
  except Exception as e:
    if state.is_cancelled:
      progress_callback.onFinished(False, "Descarga cancelada por el usuario")
    else:
      progress_callback.onFinished(False, str(e))
  finally:
    _ACTIVE.pop(download_id, None)


def pause_download(download_id):
  state = _ACTIVE.get(download_id)
  if state:
    state.is_paused = True


def resume_download(download_id):
  state = _ACTIVE.get(download_id)
  if state:
    state.is_paused = False


def cancel_download(download_id):
  state = _ACTIVE.get(download_id)
  if state:
    state.is_cancelled = True
